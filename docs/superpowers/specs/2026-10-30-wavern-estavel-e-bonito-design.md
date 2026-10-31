# Wavern: estável e bonito (design)

**Data:** 2026-10-30
**Escopo:** rodada de qualidade. Nenhum recurso novo de áudio.

## 1. Intenção e por quê

O dono parou de usar o Wavern por dois motivos:

1. **O som corta do nada.** Um mixer que derruba o áudio perde a confiança na hora.
2. **É feio.** Destoa dos outros apps dele: CrispShot (`~/Development/capta`) e Monitor/Vernio (`~/Development/estudos/monitor`).

**Sucesso** é ele voltar a deixar o Wavern ligado o dia todo sem pensar nele. O áudio nunca some. O menu parece da mesma família do CrispShot. O app tem marca própria.

## 2. Objetivos, não-objetivos, anti-objetivos

**Objetivos**
- **Zero cortes perceptíveis.** Qualquer mudança de rota, formato ou estado do sistema é tratada por uma reconstrução completa e automática.
- **Ociosidade de verdade.**
  - Com o menu fechado e nada tocando, CPU ≈ 0%.
  - Com o menu fechado e áudio tocando, só o custo do processamento de áudio.
  - Medição de hoje: 26% de CPU com o app parado, causado pela `WaveformView`.
- **Visual no estilo CrispShot.** Foi a opção A escolhida pelo dono entre três mockups.
- **Marca própria:** ícone do app, símbolo da barra de menu, logo e guia de marca. Foi o conceito 2, "Mesa de som", escolhido pelo dono.

**Não-objetivos (ficam para depois, decisão do dono)**
- Mandar cada app para uma saída diferente.
- Medidor de nível por app.
- Atalhos globais e equalizador.

**Anti-objetivos** (fracasso mesmo que "funcione")
- Uma correção que transforma corte em **silêncio permanente**. Ver §3.1 sobre `mutedWhenTapped`.
- Uma reconstrução que causa um estalo alto ou um pulo de volume para 100% antes de restaurar o volume salvo.
- Um visual bonito que volta a gastar CPU com o menu fechado.
- Perder recursos que já existem:
  - ducking;
  - perfis por dispositivo;
  - teclas de mídia;
  - volume por aba;
  - Now Playing;
  - seletor de saída;
  - volume master;
  - login item;
  - checagem de update.

## 3. Parte 1: estabilidade

Diagnóstico feito por auditoria do código e por pesquisa em fóruns e concorrentes (FineTune, SoundSource, Tapmix, thread 825780 dos Apple Developer Forums). Os números de linha se referem ao commit `f0b3256`.

### 3.1 Princípio que não muda
O `ProcessTap` usa `muteBehavior = .mutedWhenTapped` (`ProcessTap.swift:67`). Com isso, se o IOProc morrer, o app volta a tocar no volume nativo em vez de ficar mudo. **Mantenha assim.** Silêncio só acontece quando o IOProc continua rodando e entrega zeros ou toca num lugar errado. É exatamente isso que as mudanças abaixo atacam.

### 3.2 Uma única rotina de reconstrução
Hoje cada gatilho tem seu caminho parcial. Crie **uma** rotina, `rebuildAllTaps(reason:)`, que:
1. Para os IOProcs atuais imediatamente, sem esperar na fila do HAL (auditoria item 7).
2. Destrói na ordem Stop → DestroyIOProc → DestroyAggregate → DestroyTap. A pesquisa indica que reiniciar só parte disso não resolve o tap que passou a entregar zeros.
3. Recria os taps dos processos que precisam de tap: volume diferente de 1, mudo ou ducking ativo. O ganho já vem aplicado desde o primeiro buffer, sem pulo para 100%.
4. Ignora chamadas repetidas em sequência (debounce ou coalescência), porque o HAL dispara várias notificações juntas.
5. Registra o motivo no log com `os.Logger`, nível `notice`, para persistir e permitir diagnóstico depois.

### 3.3 Gatilhos que chamam a reconstrução
| Gatilho | Hoje | Novo |
|---|---|---|
| Troca do dispositivo padrão de saída | compara só o UID (`AudioProcessController.swift:171`) | compara UID **e** `AudioObjectID`; o mesmo UID com ID novo também reconstrói |
| Taxa de amostragem ou formato do dispositivo | não observa | listeners de `kAudioDevicePropertyNominalSampleRate` e `kAudioDevicePropertyStreamConfiguration` na saída atual |
| Dispositivo morreu sem deixar de ser o padrão | não observa | `kAudioDevicePropertyDeviceIsAlive` |
| AirPods entram em modo chamada (HFP) | não observa | coberto pelas duas linhas acima |
| Mac acorda do repouso | não observa | `NSWorkspace.didWakeNotification` |
| coreaudiod reinicia | não observa; o dicionário `taps` fica com objetos mortos | `kAudioHardwarePropertyServiceRestarted`; limpar o estado e reconstruir |
| Tap vivo entregando silêncio | só o 1º callback é checado (`ProcessTap.swift:122`) | vigia, ver §3.4 |

Bluetooth precisa de uma pequena espera antes de reconstruir, para o dispositivo assentar. O FineTune usa cerca de 300 ms para Bluetooth e 50 ms para o resto. Os valores exatos ficam com quem constrói.

### 3.4 Vigia
- O bloco de IO grava o horário do último callback e o horário da última amostra diferente de zero. Isso precisa ser seguro para tempo real: um ponteiro atômico, como o `gainPtr` já é.
- Um timer de 1 s, que só existe enquanto houver taps ativos, verifica cada tap e chama `rebuildAllTaps(reason: .watchdog)` em dois casos:
  - **Sem callback:** o processo está tocando (IsRunningOutput) e o tap ficou sem callback por mais de cerca de 2 s.
  - **Zeros suspeitos:** o tap teve som diferente de zero e passou a entregar só zeros, isso dentro de alguns segundos depois de um evento de dispositivo ou de formato, ou depois de acordar do repouso.
- **Zeros por si só não disparam nada.** Um app aberto e em silêncio (Discord fora de chamada, vídeo pausado) também entrega zeros e não pode causar reconstrução. **Decisão minha**, após a revisão.
- Um limite de tentativas evita loop. Se um mesmo processo falhar 3 vezes seguidas, o Wavern desiste dele assim:
  - **App mudo continua mudo, sempre (decisão do dono).** O tap de controle é trocado por um tap com `muteBehavior = .muted`, que silencia sem depender de IO.
  - **App com volume reduzido:** o tap é destruído e o app volta ao volume nativo. A linha dele mostra um aviso discreto de "sem controle". **Decisão minha.**
  - **Nova tentativa:** no próximo evento de dispositivo ou formato, ao acordar do repouso, ou quando o usuário mexer no slider.

### 3.5 Correções pontuais (da auditoria)
1. **Render por canal.** Localizar o índice do stream do tap dentro do aggregate e o `mNumberChannels` da saída, e copiar canal a canal. Saída mono recebe a média dos canais; saídas com mais canais recebem L/R nos dois primeiros. Hoje a cópia é feita por índice (`ProcessTap.swift:184-205`), o que quebra com fones que têm microfone, saída mono e HDMI multicanal.
2. **Volume 0 é mudo.** Um volume salvo como 0 é tratado como mudo e aparece como mudo na UI. Não gravar a chave de fallback global quando o volume for 0 (`AudioProcessController.swift:202-236`, `SettingsStore.swift:29-46`).
3. **Falha na leitura da lista de processos não derruba tudo.** `enumerateProcesses` retorna `nil` em erro, e o chamador pula o `apply` (`AudioProcessController.swift:375-377`).
4. **Ducking não fica preso.** O app que causa o ducking só conta como "em chamada" se estiver usando o microfone (`kAudioProcessPropertyIsRunningInput`), não só por ter a saída aberta. O engine aberto o tempo todo pelo Discord, Teams ou Slack não pode prender os outros apps em 15–50%. **Decisão minha:** os apps de chamada continuam sem tap. Assim o áudio da chamada nunca passa pelo Wavern.
5. **Vazamento de tap.** No caminho de erro de `ProcessTap.swift:82-88`, chamar `AudioHardwareDestroyProcessTap`.
6. **Aggregates órfãos.** Ao iniciar, destruir os aggregates privados do Wavern que sobraram de um crash. Identificar pelo prefixo de UID que o Wavern já usa.
7. **UID vazio.** Se `readOutputDevice` devolver `""` (falha transitória), não trocar de perfil.
8. **Rampa de ganho.** Rampa curta de cerca de 10 ms em `render` quando o ganho muda, para evitar estalo.
9. **Permissão negada que parece concedida.** Considerar a permissão concedida só depois de um callback com amostra diferente de zero, em qualquer tap. O aviso de permissão que já existe aparece só se **nenhum** tap entregou som diferente de zero desde a abertura do app, enquanto algum app está tocando e já passou um tempo razoável, de algumas dezenas de segundos. Um único app em silêncio não basta.

Item opcional, apenas se for barato: resolver o app dono de helpers XPC pelo responsible PID (auditoria item 10, não verificado).

### 3.6 CPU
- `WaveformView` (TimelineView) e qualquer animação param quando o painel fecha. O painel novo (§4.2) sabe quando abre e fecha; use isso.
- **Taps proativos ficam.** Os apps com volume ou mudo salvos continuam com tap mesmo parados. Foi a correção de setembro para "volume não aplicado ao abrir". O custo do IOProc rodando sobre zeros é aceito. A meta de CPU vale para tudo **fora** do IO: interface, timers e animações. **Decisão minha**, após a revisão.
- O ícone da barra de menu passa a ser estático. Hoje é um `waveform` animado o tempo todo enquanto algo toca. **Decisão minha:** símbolo fixo; o estado "tocando" pode ser indicado por uma leve mudança do glifo, sem animação contínua.

## 4. Parte 2: visual estilo CrispShot

Referência principal: o código do CrispShot. Tokens em `CrispShot/Editor/ToolIsland.swift:17-95`, painel em `CrispShot/App/MenuPanel.swift`, fundo em `CrispShot/Editor/BrandBackdrop.swift`, botões em `CrispShot/Backdrop/BackdropInspector.swift:478-538`. Spec de lá: `docs/superpowers/specs/2026-10-21-capta-design.md`. O mockup aprovado está em `.superpowers/brainstorm/3425-1793408703/content/visual-style.html`, opção A.

### 4.1 Tokens
Criar um `Theme.swift` único, com as cores do CrispShot e o mesmo par dark/light:
- **Acento:** `accentLight #C084FC`, `accentDeep #7C3AED`, `accentGlow #A855F7`.
- **Superfície:** tinta `#11111B` (dark) / `#F6F0FF` (light) a 0.92.
- **Blobs aurora:** `#7C3AED/#4338CA/#C084FC` (dark) e `#C084FC/#A78BFA/#E9D5FF` (light), a 0.55.
- **Texto e ícones:** `icon`, `quiet`, `hover`, `pressed`, `divider`, iguais ao CrispShot.
- **Mudo/destrutivo:** `#FF453A`.
- **Boost (>100%):** sai o laranja e entra um lilás mais quente ou o `accentGlow`. Fica com quem constrói, desde que se distinga da faixa normal.
- Sem `.accentColor` do sistema em lugar nenhum.

**Decisão minha:** suporte a modo claro e escuro, como o CrispShot.

### 4.2 Painel
- **Sai o `MenuBarExtra(.window)`**, junto com a gambiarra de transparência de 0.1 s em `WavernApp.swift:37-44`. **Entra** um `NSStatusItem` mais um `NSPanel` sem borda e não ativador, como o `KeyPanel` do CrispShot:
  - nível `.popUpMenu`;
  - posicionado 6 pt abaixo do item;
  - fecha ao clicar fora ou com Esc.
- **Dimensões:** largura 300, altura conforme o conteúdo, com limite máximo e rolagem. Raio 14 contínuo e borda de 0.5 pt em `divider`.
- **Fundo:** `BrandSurface`, ou seja, vibrancy + tinta + aurora. Com Reduce Transparency, cor sólida.
- **Abertura:** `spring(duration: 0.38, bounce: 0.22)`, escala de 0.96 a 1 a partir do topo, com fade. Com Reduce Motion, ease-out de 0.16 s.

**Decisão minha:** copiar o padrão do CrispShot em vez de estilizar o `MenuBarExtra`, porque é o único jeito de ter a animação e o controle de abrir/fechar que a §3.6 precisa.

### 4.3 Layout (de cima para baixo, igual ao mockup A)
1. **Cabeçalho:** "Wavern" em 13 semibold e, à direita, um chip com o dispositivo de saída que abre o seletor existente.
2. **Tile do volume master:** ícone, slider e porcentagem.
3. **Rótulo de seção "Tocando agora"** (10.5 semibold, `quiet`), seguido dos tiles dos apps tocando.
   - O app tocando com Now Playing ganha o **tile em destaque**: gradiente lilás a 0.95 e brilho, com texto branco, artwork e título da faixa.
   - **Decisão minha:** só há um destaque, que é o app em foco: o último que começou a tocar, ou o que está sob o mouse.
4. Apps em linger, mudos ou sem som ficam com a opacidade reduzida. Mudo aparece a 0.55, como no mockup.
5. **Rodapé:** linha divisória e chips no lugar de `Picker`/`Toggle`/botões padrão.
   - O nível de ducking vira um chip com menu.
   - As teclas de mídia, o login item, o update e o "Sair" ficam num chip ⚙︎ que abre um menu.
   - Todas as opções que existem hoje continuam acessíveis.

**Medidas:** padding externo 12, espaço de 6 entre tiles, tile com raio 12 e 9 pt de padding vertical, chips com raio 8.

**Tipografia:** só a fonte do sistema. Nome do app 12 medium e subtítulo 10 em `quiet`. Porcentagens com `.monospacedDigit()`.

**Componentes:**
- O slider mantém a estrutura atual do `VolumeSlider`, com preenchimento em gradiente `#C084FC→#7C3AED`. Dentro do tile em destaque, o preenchimento é branco.
- Os SF Symbols usam peso regular e renderização hierárquica.
- Hover em tiles e chips usa `.easeOut(0.12)`.

### 4.4 O que sai
- `VisualEffectBackground.swift` como está hoje, porque vira o `BrandSurface`.
- Cores semânticas `.secondary`/`.tertiary` no menu.
- Os estilos de controle padrão.

A `WaveformView` só fica se couber no visual novo e respeitar a §3.6. Fica com quem constrói.

## 5. Parte 3: marca

O padrão é o do Monitor (`~/Development/estudos/monitor/docs/brand/`, `scripts/make-icon.swift`). O conceito aprovado é o **2, "Mesa de som"**, em `.superpowers/brainstorm/3425-1793408703/content/logo.html`: três trilhos verticais com botões de fader em alturas crescentes, formando uma onda. A linha da onda passa pelos botões em lilás gradiente com brilho, sobre um quadrado escuro arredondado no estilo do ícone do CrispShot.

O mockup é um rascunho de direção. A versão final precisa de acabamento: botões centralizados nos trilhos, proporções que funcionem em 16 px, e brilho e gradiente iguais aos do CrispShot.

Entregáveis em `docs/brand/`:
- `mark.svg`: o símbolo sozinho.
- `logo.svg`: o símbolo mais "wavern" em minúsculas.
- `icon.png`: 1024 px.
- `README.md`: a paleta e os usos, no formato do README do Monitor.
- **Ícone do app:** um asset catalog ou `.icns` gerado por um script Swift (`scripts/make-icon.swift`), com o `project.yml` configurado para usá-lo. Hoje o app não tem ícone.
- **Glifo da barra de menu:** versão monocromática como *template image*, que se adapta à barra clara e escura, legível em 18 pt.

## 6. Restrições
- macOS 14.4+ (deployment target atual). `glassEffect` só vale para macOS 26, com fallback, como no CrispShot.
- Build e assinatura seguem a memória do projeto: `DEVELOPER_DIR` para o xcodebuild e certificado self-signed. Um build ad-hoc invalida a permissão de captura de áudio (TCC).
- Commits sem atribuição de IA. O release-please cuida da versão, então use Conventional Commits.
- O bloco de IO precisa continuar seguro para tempo real: sem alocação, sem lock, sem log e sem ARC no caminho quente.

## 7. Como saber que ficou pronto
- **Estabilidade:** cada gatilho da §3.3 exercitado de verdade com áudio tocando num app com volume ajustado.
  - Trocar de saída várias vezes seguidas.
  - Mudar a taxa de amostragem pelo Audio MIDI Setup.
  - Conectar e desconectar AirPods, e abrir o microfone deles numa chamada.
  - Dormir e acordar o Mac.
  - `sudo killall coreaudiod`.

  Em todos os casos o som volta sozinho em até cerca de 2 s, com o volume salvo, sem pulo para 100%. O log mostra o motivo da reconstrução.
- **CPU:** com o menu fechado e nada tocando, sem taps proativos, menos de 0.5% de média em 1 min (`top`). Com taps proativos, o `sample` mostra apenas threads de IO de áudio. Com o menu fechado e áudio tocando, sem frames de SwiftUI ou Metal no `sample`.
- **Visual:** capturas do painel em dark e light, lado a lado com o mockup A.
- **Marca:** o ícone aparece no Finder e no Dock (quando visível), e o glifo aparece na barra clara e na escura.
- **Regressão:** todos os recursos listados nos anti-objetivos continuam funcionando.

## 8. O que fica com quem constrói
- A ordem das partes. Sugestão: estabilidade → CPU → painel/visual → marca.
- Os valores exatos de debounce, espera do Bluetooth e limites do vigia.
- A estrutura de arquivos, que pode reaproveitar e dividir os existentes.
- Como testar o vigia de forma automatizada, se for barato. Exemplo: uma função pura que decide "precisa reconstruir?", com teste.
