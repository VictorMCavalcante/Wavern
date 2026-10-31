# Wavern estável e bonito: plano de implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fazer o Wavern parar de cortar o som. Ele deve se recuperar sozinho de qualquer mudança de dispositivo, formato ou estado do sistema, não gastar CPU parado, ganhar o visual do CrispShot e ter marca própria.

**Architecture:**
- **Recuperação:** uma única rotina `rebuildAllTaps(reason:)`, chamada por todos os gatilhos e por um vigia de 1 s que lê timestamps gravados pelo bloco de IO.
- **Lógica pura:** a lógica decidível sem hardware (veredito do vigia, identidade de dispositivo, mixagem por canal) fica em arquivos que só importam Foundation/Accelerate e é verificada por um executável de checks compilado com `swiftc`.
- **UI:** troca `MenuBarExtra` por `NSStatusItem` + `NSPanel`, portados do CrispShot. A hierarquia SwiftUI só existe enquanto o painel está aberto.

**Tech Stack:** Swift 5, SwiftUI, AppKit, Core Audio process taps (macOS 14.4+), Accelerate, xcodegen.

**Spec:** `docs/superpowers/specs/2026-10-30-wavern-estavel-e-bonito-design.md`. Leia junto com este plano. As seções citadas como §x.y são de lá.

## Global Constraints

- Deployment target macOS 14.4. `glassEffect` só aparece atrás de `if #available(macOS 26, *)`.
- O bloco de IO não pode alocar, travar, logar nem fazer retain/release. Estado compartilhado com ele é ponteiro alocado uma vez, no padrão do `gainPtr`.
- **Manter `muteBehavior = .mutedWhenTapped` nos taps de controle** (§3.1).
- **Mudo é sempre mudo:** nenhum caminho de falha pode fazer um app mudo voltar a tocar.
- Nada de pulo para 100%. Todo tap novo nasce com o ganho efetivo já aplicado.
- O texto da UI continua em inglês, como hoje. **Decisão de plano:** o spec não pediu tradução e todo o texto atual é inglês.
- Cores só de `Theme.swift`. Nenhum `.accentColor` e nenhum `.secondary`/`.tertiary` no painel.
- **Build rápido:**
  ```
  swiftc -typecheck -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk -target arm64-apple-macos14.4 -swift-version 5 -parse-as-library Sources/Wavern/*.swift
  ```
- **Build real:**
  ```
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Wavern.xcodeproj -scheme Wavern -configuration Release -derivedDataPath "$SCRATCH/dd" CODE_SIGN_IDENTITY="Wavern Signing" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
  ```
  Nunca use assinatura ad-hoc para instalar: ela quebra a permissão TCC de captura.
- Arquivo novo exige `xcodegen generate`.
- **Instalar para testar:**
  ```
  osascript -e 'quit app "Wavern"'; rm -rf /Applications/Wavern.app; cp -R "$SCRATCH/dd/Build/Products/Release/Wavern.app" /Applications/; open /Applications/Wavern.app
  ```
  Nunca rode o build de dev ao lado da cópia instalada.
- **Logs:** `os.Logger` com o subsystem atual. Os eventos de recuperação usam `.notice`, para persistirem em `log show`.
- **Commits:** Conventional Commits, **sem nenhuma linha de atribuição de IA** (`Co-Authored-By`, `Generated with` etc.). Regra explícita do dono do repo.

## Review Focus

1. **Trocas rápidas de saída** (AirPods ↔ alto-falante, 5 vezes em 3 s). Ao final, o áudio sai no dispositivo final com o volume certo e não sobra nenhum aggregate `com.wavern.aggregate.*` além de um por tap vivo. *Testado na Task 4, passo de verificação manual.*
2. **App fecha com a reconstrução em andamento.** Não pode haver crash nem tap/aggregate órfão. *Task 4, passo manual.*
3. **Saída mono, estéreo ou com 6+ canais, e aggregate com stream de microfone antes do tap.** O áudio do app sai correto. *Task 2, checks `mixMonoOut`, `mixMultichannelOut`, `mixPicksLastInputStream`.*
4. **Volume 0 salvo por versões antigas** (chave `wavern.vol.*` = 0). O app abre como mudo, não como "100% com slider em 0". *Task 3, check `zeroVolumeReadsAsMuted`.*
5. **Painel aberto durante uma troca de dispositivo ou reconstrução.** A UI acompanha, nada fica preso em erro e o painel não fecha sozinho. *Task 8, passo manual.*

---

## Estrutura de arquivos

| Arquivo | Responsabilidade |
|---|---|
| `Sources/Wavern/TapHealth.swift` (novo) | Puro. Veredito do vigia, política de desistência, decisão de troca de dispositivo |
| `Sources/Wavern/AudioMix.swift` (novo) | Puro. Cópia canal a canal com ganho e rampa, usada pelo IO |
| `Tests/LogicChecks/main.swift` (novo) | Executável de checks com `assert`, compilado junto com os arquivos puros |
| `scripts/check.sh` (novo) | Compila e roda os checks |
| `scripts/list-aggregates.swift` (novo) | Ferramenta de verificação: lista aggregates e taps do Wavern vivos no HAL |
| `Sources/Wavern/ProcessTap.swift` | Usa `AudioMix`, grava timestamps, modo `muteOnly`, corrige vazamento |
| `Sources/Wavern/SettingsStore.swift` | Volume 0 vira mudo |
| `Sources/Wavern/AudioProcess.swift` | Novo campo `isUsingInput` |
| `Sources/Wavern/AudioProcessController.swift` | Identidade do dispositivo, `enumerateProcesses` opcional, `ensureTap(initialGain:)` |
| `Sources/Wavern/AudioProcessController+Recovery.swift` (novo) | `rebuildAllTaps`, gatilhos, vigia, desistência |
| `Sources/Wavern/AudioProcessController+Ducking.swift` | Ducker ativo = usando microfone |
| `Sources/Wavern/Theme.swift` (novo) | Tokens do CrispShot |
| `Sources/Wavern/BrandSurface.swift` (novo, substitui `VisualEffectBackground.swift`) | Fundo vibrancy + tinta + aurora |
| `Sources/Wavern/StatusPanel.swift` (novo) | `NSStatusItem` + `NSPanel`, abrir/fechar, glifo da barra |
| `Sources/Wavern/MenuView.swift`, `AudioProcessRow.swift`, `VolumeSlider.swift` | Visual novo |
| `Sources/Wavern/Chip.swift` (novo) | Chip e botão do rodapé |
| `Sources/Wavern/WavernApp.swift` | `MenuBarExtra` sai e entra o `StatusPanel` |
| `scripts/make-icon.swift`, `Resources/AppIcon.icns`, `docs/brand/*` (novos) | Marca |

---

### Task 1: Lógica pura do vigia e da troca de dispositivo, com harness de checks

**Files:**
- Create: `Sources/Wavern/TapHealth.swift`
- Create: `Tests/LogicChecks/main.swift`
- Create: `scripts/check.sh`

**Interfaces:**
- Produces:
  ```swift
  struct TapSnapshot {
      var isPlaying: Bool          // IsRunningOutput do processo
      var activatedAt: TimeInterval
      var lastCallback: TimeInterval   // 0 = nunca
      var lastNonZero: TimeInterval    // 0 = nunca
  }
  enum TapVerdict: Equatable { case healthy, stalled, silentAfterEvent }
  enum TapHealth {
      static let stallTimeout: TimeInterval = 2
      static let eventWindow: TimeInterval = 15
      static let soundBeforeEvent: TimeInterval = 5
      static func verdict(_ s: TapSnapshot, now: TimeInterval, lastEvent: TimeInterval?) -> TapVerdict
  }
  struct GiveUpPolicy {
      static let maxStrikes = 3
      private(set) var strikes: [UInt32: Int]
      mutating func strike(_ id: UInt32) -> Bool   // true = desistir agora
      mutating func reset()
  }
  struct DeviceIdentity: Equatable { let id: UInt32; let uid: String }
  enum DeviceChange: Equatable { case none, sameProfileRebuild, newProfile }
  func classifyDeviceChange(old: DeviceIdentity, new: DeviceIdentity) -> DeviceChange
  ```
  Os tempos estão em segundos monotônicos (`ProcessInfo.processInfo.systemUptime`). `UInt32` é o `AudioObjectID`; o arquivo não importa CoreAudio.

**Regras do `verdict`:**
- `.stalled`: `isPlaying` e `now - max(lastCallback, activatedAt) > stallTimeout`.
- `.silentAfterEvent`: todas as condições abaixo valem ao mesmo tempo.
  - `isPlaying`, e existe `lastEvent`.
  - O tap teve som pouco antes do evento: `lastNonZero > 0` e `lastNonZero >= lastEvent - soundBeforeEvent`.
  - Não houve som depois do evento: `lastNonZero < lastEvent`.
  - O silêncio pós-evento está dentro da janela: `stallTimeout < now - lastEvent < eventWindow`.
- Caso contrário, `.healthy`. Zeros sem evento nunca disparam.

**Regras do `classifyDeviceChange`:**
- `new.uid` vazio → `.none` (§3.5.7).
- `uid` diferente → `.newProfile`.
- Mesmo `uid` com `id` diferente → `.sameProfileRebuild`.
- Mesmo `uid` e mesmo `id` → `.none`.

- [ ] **Step 1: Escrever os checks que falham**

`Tests/LogicChecks/main.swift`: cada função de check usa `assert` e imprime `ok <nome>`. O `main` chama todas.
```swift
func playing(_ act: Double = 0, cb: Double = 0, nz: Double = 0) -> TapSnapshot {
    TapSnapshot(isPlaying: true, activatedAt: act, lastCallback: cb, lastNonZero: nz)
}
func verdictStalled()        { assert(TapHealth.verdict(playing(cb: 10), now: 12.5, lastEvent: nil) == .stalled) }
func verdictNotPlayingIsHealthy() { var s = playing(cb: 1); s.isPlaying = false
                                    assert(TapHealth.verdict(s, now: 100, lastEvent: nil) == .healthy) }
func verdictFreshTapNotStalled() { assert(TapHealth.verdict(playing(10), now: 11, lastEvent: nil) == .healthy) }
func verdictSilentAppIsHealthy() { assert(TapHealth.verdict(playing(cb: 99.9, nz: 0), now: 100, lastEvent: nil) == .healthy) }
func verdictZerosWithoutEventHealthy() { assert(TapHealth.verdict(playing(cb: 99.9, nz: 50), now: 100, lastEvent: nil) == .healthy) }
func verdictSilentAfterEvent()  { assert(TapHealth.verdict(playing(cb: 99.9, nz: 89), now: 93, lastEvent: 90) == .silentAfterEvent) }
func verdictSoundResumedAfterEvent() { assert(TapHealth.verdict(playing(cb: 99.9, nz: 92), now: 95, lastEvent: 90) == .healthy) }
func verdictEventTooOld()       { assert(TapHealth.verdict(playing(cb: 99.9, nz: 89), now: 120, lastEvent: 90) == .healthy) }
func verdictWasSilentBeforeEvent() { assert(TapHealth.verdict(playing(cb: 99.9, nz: 70), now: 93, lastEvent: 90) == .healthy) }
func giveUpAfterThree() { var p = GiveUpPolicy(); assert(!p.strike(7)); assert(!p.strike(7)); assert(p.strike(7))
                          p.reset(); assert(!p.strike(7)) }
func deviceChanges() {
    let a = DeviceIdentity(id: 1, uid: "X")
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 1, uid: "X")) == .none)
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 9, uid: "X")) == .sameProfileRebuild)
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 9, uid: "Y")) == .newProfile)
    assert(classifyDeviceChange(old: a, new: DeviceIdentity(id: 0, uid: "")) == .none)
}
```

`scripts/check.sh`:
```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="${TMPDIR:-/tmp}/wavern-checks"
swiftc -Onone -swift-version 5 -target arm64-apple-macos14.4 \
  -sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk \
  Sources/Wavern/TapHealth.swift Tests/LogicChecks/main.swift -o "$out"
"$out"
```
As tasks seguintes adicionam os arquivos delas à linha do `swiftc` editando este script. Mantenha `-Onone`: com `-O`, os `assert` são removidos.

- [ ] **Step 2:** Rodar `bash scripts/check.sh`. Esperado: erro de compilação "cannot find 'TapHealth' in scope".
- [ ] **Step 3:** Implementar `Sources/Wavern/TapHealth.swift` com as interfaces e regras acima (só `import Foundation`).
- [ ] **Step 4:** Rodar `bash scripts/check.sh`. Esperado: todas as linhas `ok …` e saída 0.
- [ ] **Step 5:** Rodar `xcodegen generate` e o typecheck rápido. Esperado: sem erros.
- [ ] **Step 6: Commit**
  ```bash
  git add Sources/Wavern/TapHealth.swift Tests/LogicChecks scripts/check.sh Wavern.xcodeproj
  git commit -m "feat(recovery): pure watchdog verdict and device-change classification"
  ```

---

### Task 2: Render por canal, rampa de ganho, timestamps no IO e tap só-mudo

**Files:**
- Create: `Sources/Wavern/AudioMix.swift`
- Modify: `Sources/Wavern/ProcessTap.swift` (todo o arquivo; render nas linhas 177-207, IO block nas 119-126, vazamento nas 82-88)
- Modify: `Tests/LogicChecks/main.swift`, `scripts/check.sh`

**Interfaces:**
- Produces:
  ```swift
  enum AudioMix {
      /// Mixa o tap (último buffer de entrada) para todos os buffers de saída.
      /// `gainState[0]` = ganho alvo (escrito pela UI); `gainState[1]` = último
      /// ganho aplicado (só o IO escreve). Rampa linear de [1] para [0] ao longo
      /// do buffer. Retorna true se a entrada tinha alguma amostra != 0.
      static func render(input: UnsafeMutableAudioBufferListPointer,
                         output: UnsafeMutableAudioBufferListPointer,
                         gainState: UnsafeMutablePointer<Float>) -> Bool
  }
  final class ProcessTap {
      enum Mode { case control, muteOnly }
      init(process: AudioProcess, mode: Mode = .control)
      let mode: Mode
      var gain: Float { get set }                 // escreve gainState[0]
      var lastCallback: TimeInterval { get }      // 0 = nunca
      var lastNonZero: TimeInterval { get }       // 0 = nunca
      private(set) var activatedAt: TimeInterval
  }
  ```
  `onFirstIO` **sai**. O vigia (Task 5) decide a permissão a partir de `lastNonZero`.

**Regras do `render`:**
- O tap é **o último** buffer de entrada (`input[input.count - 1]`). Se o aggregate expõe o microfone do dispositivo, esse stream vem antes. Para aceitar isso, registre no log, uma vez por tap e fora do IO (em `activate`), o número de streams de entrada do aggregate (`kAudioDevicePropertyStreams`, scope input).
  `// ponytail: assume tap = último stream de entrada; se o log mostrar outra ordem, procurar o stream pelo kAudioStreamPropertyStartingChannel do tap`
- Canais de entrada e saída vêm de `mNumberChannels` (buffers intercalados).
  - Saída com 1 canal: média de L e R.
  - Saída com N ≥ 2: L e R nos canais 0 e 1, zero no resto.
  - Entrada mono: duplica.
  - Outros buffers de saída: zero.
- Rampa: ganho linear de `gainState[1]` até `gainState[0]` dentro do buffer. Ao final, `gainState[1] = gainState[0]`.
- Detecção de som: `vDSP_maxmgv` na entrada, `> 0`.

**Mudanças no `ProcessTap`:**
- Os campos `gainState` (2 × Float) e `times` (2 × Double: callback, nonZero) são alocados uma vez, no padrão atual de `gainPtr`.
- O bloco de IO só captura esses ponteiros (sem `self`). Ele grava `times[0]` a cada callback e `times[1]` quando `render` retorna true. A hora vem de `AudioTimeStamp.mHostTime` convertido em segundos, para não chamar nada fora do IO. A conversão usa um fator `mach_timebase_info` calculado uma vez em `init`.
- Os getters `lastCallback`/`lastNonZero` convertem para a mesma base de `ProcessInfo.systemUptime`. Em Apple Silicon, `mach_absolute_time` × timebase coincide com `systemUptime`; documente isso num comentário.
- Inicialização: `gainState[1]` começa igual a `gainState[0]`, para o primeiro buffer não fazer rampa a partir de 1.
- Nas linhas 82-88, o throw depois de criar o tap passa a destruir o tap antes (§3.5.5).
- `.muteOnly`: cria só o `CATapDescription` com `muteBehavior = .muted` e `isPrivate = true`, sem aggregate e sem IOProc. `isActive` vira true após a criação.

- [ ] **Step 1: Checks que falham.** Adicionar a `main.swift` um helper que monta `AudioBufferList` a partir de arrays de `Float` (com `AudioBufferList.allocate(maximumBuffers:)`) e os checks abaixo:
  - `mixStereoUnity`: entrada `[1,-1, 0.5,-0.5]` com 2 canais, saída 2 canais, ganho 1→1. Saída idêntica e retorno true.
  - `mixMonoOut`: entrada `[1,0, 0,1]` com 2 canais, saída 1 canal. Saída `[0.5, 0.5]`.
  - `mixMultichannelOut`: entrada `[1,2]` com 2 canais e 1 frame, saída 6 canais. Saída `[1,2,0,0,0,0]`.
  - `mixPicksLastInputStream`: duas entradas, o mic `[9,9]` e o tap `[1,1]`, saída 2 canais. Saída `[1,1]`.
  - `mixRamp`: `gainState = [1, 0]`, entrada constante 1 com 4 frames estéreo. Os valores de L crescem estritamente, o último é `< 1` e ≥ 0.75, e depois `gainState[1] == 1`.
  - `mixSilenceReportsFalse`: entrada só de zeros. Retorno false.
- [ ] **Step 2:** Adicionar `Sources/Wavern/AudioMix.swift` ao `swiftc` de `check.sh` e rodar. Esperado: erro "cannot find 'AudioMix'".
- [ ] **Step 3:** Implementar `AudioMix.render` (com `import Accelerate` e `import CoreAudio`).
- [ ] **Step 4:** `bash scripts/check.sh`. Esperado: todos `ok`.
- [ ] **Step 5:** Aplicar as mudanças no `ProcessTap` descritas acima. Remover `onFirstIO` e `firedFirstIO`. Em `AudioProcessController.ensureTap`, apagar a linha `tap.onFirstIO = …`; a Task 5 reconecta a permissão. Rodar o typecheck rápido. Esperado: sem erros.
- [ ] **Step 6:** Rodar o build real e instalar. Tocar música no Spotify ou Music e baixar o slider para 30%. Esperado: o volume cai suave, sem estalo. No `log show --last 2m --predicate 'process == "Wavern"'` aparece a contagem de streams de entrada do aggregate.
- [ ] **Step 7: Commit**
  ```bash
  git add Sources/Wavern/AudioMix.swift Sources/Wavern/ProcessTap.swift Sources/Wavern/AudioProcessController.swift Tests scripts Wavern.xcodeproj
  git commit -m "fix(tap): channel-aware render with gain ramp; record IO timestamps; no tap leak on setup error"
  ```

---

### Task 3: Volume 0 salvo significa mudo

**Files:**
- Modify: `Sources/Wavern/SettingsStore.swift:29-46`
- Modify: `Sources/Wavern/AudioProcessController.swift:202-207`
- Modify: `Tests/LogicChecks/main.swift`, `scripts/check.sh`

**Interfaces:**
- `SettingsStore.volume(for:)` nunca retorna 0. Um valor salvo `≤ 0` vira `nil`.
- `SettingsStore.isMuted(_:)` retorna true também quando o volume salvo (no perfil ou no fallback) é `≤ 0`.
- `SettingsStore.setVolume(_:for:)` com `value ≤ 0` chama `setMuted(true, for:)` e não escreve volume em nenhuma das duas chaves. O volume anterior é preservado para o desmutar.
- `AudioProcessController.setVolume` com `value ≤ 0` passa a pôr o processo em `muted`, mantendo `volumes[id]` anterior.

- [ ] **Step 1: Checks que falham.** Em `main.swift`, criar a store com `UserDefaults(suiteName: "wavern.checks.\(UUID())")!`, dentro de `MainActor.assumeIsolated { … }`.
  - `zeroVolumeReadsAsMuted`: `defaults.set(Float(0), forKey: "wavern.vol.com.x")`. Então `store.volume(for: "com.x") == nil` e `store.isMuted("com.x") == true`.
  - `settingZeroMutesAndKeepsVolume`: `setVolume(0.4)`, depois `setVolume(0)`. Então `isMuted == true` e `volume(for:) == 0.4`.
  - `positiveVolumeUnmutes`: depois do anterior, `setVolume(0.7)`. Então `isMuted == false` e `volume == 0.7`.
- [ ] **Step 2:** Adicionar `Sources/Wavern/SettingsStore.swift` ao `check.sh` e rodar. Esperado: `zeroVolumeReadsAsMuted` falha no assert.
- [ ] **Step 3:** Implementar as regras em `SettingsStore` e em `AudioProcessController.setVolume`.
- [ ] **Step 4:** `bash scripts/check.sh` (todos `ok`) e o typecheck rápido.
- [ ] **Step 5: Commit**
  ```bash
  git commit -am "fix(settings): a saved volume of 0 is mute, never a silent unmuted app"
  ```

---

### Task 4: Rotina única de reconstrução e seus gatilhos

**Files:**
- Create: `Sources/Wavern/AudioProcessController+Recovery.swift`
- Create: `scripts/list-aggregates.swift`
- Modify: `Sources/Wavern/AudioProcessController.swift`. Nas linhas 160-184 (identidade do dispositivo), 239-266 (`ensureTap`), 274-287 (`pruneVanished`), 293-309 (`start`) e 370-379 (`enumerateProcesses`).

**Interfaces:**
- Consumes: `classifyDeviceChange`, `DeviceIdentity` (Task 1) e `ProcessTap.Mode` (Task 2).
- Produces:
  ```swift
  enum RebuildReason: String { case deviceChanged, sameDeviceNewID, formatChanged, deviceDied, wake, serviceRestarted, watchdog }
  extension AudioProcessController {
      func rebuildAllTaps(reason: RebuildReason)      // coalescida
      func needsTap(_ p: AudioProcess) -> Bool         // mudo || volume != 1 || (isDucked(p) && p.isPlaying)
      func effectiveGain(for p: AudioProcess) -> Float // regra atual de applyGain
      var lastRouteEvent: TimeInterval? { get }        // systemUptime do último gatilho ≠ watchdog
  }
  // em AudioProcessController:
  var currentDevice: DeviceIdentity    // substitui o uso de settings.deviceUID para comparar
  let teardownQueue: DispatchQueue     // "com.wavern.teardown", separada de halQueue
  ```

**Comportamento:**
1. **`rebuildAllTaps(reason:)`:**
   - Registra `.notice` com o motivo.
   - Coalesce: cancela o `DispatchWorkItem` pendente e agenda um novo depois de **300 ms** se o transport do dispositivo atual for Bluetooth ou BluetoothLE, ou **50 ms** se não for.
   - Quando o item roda, ele:
     - move todos os `taps` atuais para `teardownQueue.async { tap.invalidate() }`. Os objetos antigos nunca são reativados, então a fila separada não cria corrida;
     - esvazia `taps` e `tapErrors`;
     - chama `ensureTap(for:initialGain:)` para cada processo em `processes` com `needsTap`.
   - Se o motivo não for `.watchdog`, atualiza `lastRouteEvent`.
2. **`ensureTap(for:initialGain:)`:** o ganho vai para o tap **antes** do `halQueue.async { activate() }`. `applyGain` passa a chamar `ensureTap(for: p, initialGain: effectiveGain(for: p))`.
3. **`handleOutputDeviceChange`:** usa `classifyDeviceChange(old: currentDevice, new: lido)`.
   - `.none`: retorna.
   - `.newProfile`: faz o comportamento atual (troca `settings.deviceUID`, limpa `volumes`/`muted`/`restoredIDs`, `reload()`) e chama `rebuildAllTaps(.deviceChanged)` no lugar do loop de invalidate.
   - `.sameProfileRebuild`: `attachOutputDevice(novo id)` e `rebuildAllTaps(.sameDeviceNewID)`, mantendo os volumes.
4. **Gatilhos novos:**
   - **Sample rate, configuração de stream e dispositivo vivo:** em `attachOutputDevice(_:)` (`+OutputDevice.swift:34`), para o id novo:
     - `listen(kAudioDevicePropertyNominalSampleRate)` → `rebuildAllTaps(.formatChanged)`;
     - `listen(kAudioDevicePropertyStreamConfiguration, scope: output)` → `rebuildAllTaps(.formatChanged)`;
     - `listen(kAudioDevicePropertyDeviceIsAlive)` → se o valor lido for 0, `rebuildAllTaps(.deviceDied)`.

     O `unlisten(outputDeviceID)` que já existe remove todos eles.
   - **Wake:** `NSWorkspace.shared.notificationCenter`, `didWakeNotification` → `rebuildAllTaps(.wake)`. Registrar em `start()`.
   - **Reinício do serviço:** `listen(kAudioHardwarePropertyServiceRestarted, on: .system)` faz o seguinte:
     - esvazia `listeners` **sem** chamar Remove, porque os objetos morreram, e esvazia `taps` sem invalidar;
     - registra de novo os listeners de sistema de `start()`. Extraia `registerSystemListeners()` para não duplicar código;
     - chama `attachOutputDevice` com o padrão atual, depois `reload()` e `rebuildAllTaps(.serviceRestarted)`.
5. **`enumerateProcesses() -> [AudioProcess]?`:** retorna `nil` em erro, e `reload` pula o `apply` quando recebe `nil`. Ainda assim precisa zerar `reloadInFlight` e honrar `reloadPending`.
6. **Aggregates órfãos (§3.5.6):** já resolvido por `ProcessTap.reapLeakedDevices()` na abertura; não mexer.
7. **`readOutputDevice`:** um `uid` vazio já cai em `.none` pela classificação. Em `start()`, se o `uid` vier vazio, não sobrescreva `settings.deviceUID`.

`scripts/list-aggregates.swift` é um script de ~20 linhas que roda com `swift scripts/list-aggregates.swift`. Ele lê `kAudioHardwarePropertyDevices` e `kAudioHardwarePropertyTapList` e imprime a contagem de aggregates com prefixo `com.wavern.aggregate.` e de taps com nome iniciando em `Voulum-`, mais os UIDs.

- [ ] **Step 1:** Implementar os itens 1-6. Rodar `bash scripts/check.sh` e o typecheck rápido. Esperado: sem erros.
- [ ] **Step 2:** Build real e instalar. Com o Spotify tocando a 40% e outro app mudo, trocar a saída pelo seletor do macOS. Esperado:
  - o som volta em ≤ 2 s, a 40%;
  - o app mudo continua mudo;
  - o `log show --last 2m --predicate 'process == "Wavern"' | grep -i rebuild` mostra `deviceChanged`.
- [ ] **Step 3:** Mudar a taxa da saída no Audio MIDI Setup (44,1 ↔ 48 kHz). Esperado: um `formatChanged` no log e o áudio continua no volume ajustado.
- [ ] **Step 4 (Review Focus 1):** Trocar AirPods ↔ alto-falante 5 vezes em cerca de 3 s, por exemplo com um loop de `SwitchAudioSource` se estiver instalado, ou com cliques. Depois rodar `swift scripts/list-aggregates.swift`. Esperado: o número de aggregates é igual ao número de taps vivos, o áudio sai no último dispositivo e o volume está correto.
- [ ] **Step 5 (Review Focus 2):** Trocar de dispositivo e, em menos de 1 s, sair do Wavern (Quit). Abrir de novo e rodar `swift scripts/list-aggregates.swift` antes de tocar qualquer coisa. Esperado: nenhum crash report novo em `~/Library/Logs/DiagnosticReports/Wavern*`. O reaper de abertura (`ProcessTap.reapLeakedDevices`, que já existe) deixa 0 órfãos.
- [ ] **Step 6:** Rodar `pmset sleepnow`, acordar e tocar. Esperado: `wake` no log e o som no volume salvo. Depois rodar `sudo killall coreaudiod` com música tocando. Esperado: `serviceRestarted` no log, o som volta em poucos segundos no volume salvo e os sliders continuam funcionando.
- [ ] **Step 7: Commit**
  ```bash
  git add -A Sources/Wavern scripts/list-aggregates.swift Wavern.xcodeproj
  git commit -m "fix(recovery): single rebuild path for device, format, wake and coreaudiod restart"
  ```

---

### Task 5: Vigia, desistência e permissão por som real

**Files:**
- Modify: `Sources/Wavern/AudioProcessController+Recovery.swift`
- Modify: `Sources/Wavern/AudioProcessController.swift` (estado publicado)
- Modify: `Sources/Wavern/AudioProcessRow.swift` (aviso "sem controle")

**Interfaces:**
- Consumes: `TapHealth.verdict`, `GiveUpPolicy` (Task 1), `ProcessTap.lastCallback/lastNonZero/activatedAt/mode` (Task 2), `rebuildAllTaps`, `lastRouteEvent` (Task 4).
- Produces:
  ```swift
  @Published private(set) var uncontrolled: Set<AudioObjectID>   // desistidos com volume reduzido
  func isUncontrolled(_ p: AudioProcess) -> Bool
  ```

**Comportamento:**
- **Timer:** um `Timer` de 1 s em main, que existe só enquanto `taps` não estiver vazio. Ele é criado em `ensureTap` e invalidado quando `taps` esvazia.
- **Em cada tick, para cada tap com `mode == .control` e `isActive`:**
  - monta o `TapSnapshot` (`isPlaying` vem de `processes`) e calcula o `verdict` com `now = systemUptime` e `lastEvent = lastRouteEvent`;
  - se o veredito for diferente de `.healthy` e `giveUp.strike(id)` retornar true, **desiste**:
    - processo mudo: invalida o tap de controle e cria `ProcessTap(process:, mode: .muteOnly)`;
    - senão: invalida o tap, remove de `taps` e insere em `uncontrolled`;
  - se o veredito for diferente de `.healthy` e não houver desistência: `rebuildAllTaps(.watchdog)`. No máximo uma vez por tick.
- **Permissão:** se algum tap tiver `lastNonZero > 0`, chama `rememberPermissionGranted()`. Isso substitui o `onFirstIO` removido na Task 2. O aviso que já existe no rodapé continua aparecendo enquanto `audioPermissionGranted == false`.
- **Reset da desistência:** `giveUp.reset()` e `uncontrolled = []` em todo `rebuildAllTaps` cujo motivo não é `.watchdog`. Para um processo específico, `setVolume` e `toggleMute` removem esse processo de `uncontrolled` e do `GiveUpPolicy`. Para isso, adicione `mutating func clear(_ id: UInt32)` ao `GiveUpPolicy` e um check `giveUpClearOne` na Task 1 de `main.swift`.
- **`needsTap`:** retorna false para processos em `uncontrolled`, para a reconstrução não ressuscitar o loop.
- **UI:** na linha do app em `uncontrolled`, mostrar o texto `"No control — tap to retry"` com o SF Symbol `exclamationmark.triangle`, na cor `Theme.quiet`. O clique chama `setVolume` com o volume atual.

- [ ] **Step 1:** Adicionar o check `giveUpClearOne` e implementar `clear(_:)`. Rodar `bash scripts/check.sh`. Esperado: todos `ok`.
- [ ] **Step 2:** Implementar o vigia, a desistência, a permissão e a UI. Typecheck rápido.
- [ ] **Step 3:** Build real, instalar e verificar:
  - com o Spotify tocando a 40%, `log show --last 1m --predicate 'process == "Wavern"' | grep -i watchdog` → vazio, o vigia não dispara com áudio saudável;
  - pausar o Spotify por 30 s → continua vazio, porque app em silêncio não dispara;
  - Discord aberto fora de chamada, com volume salvo ≠ 1 → nenhum `watchdog` em 1 min.
- [ ] **Step 4: Commit**
  ```bash
  git commit -am "feat(recovery): watchdog rebuilds dead taps; give up keeps muted apps muted"
  ```

---

### Task 6: Ducking só quando o app de chamada usa o microfone

**Files:**
- Modify: `Sources/Wavern/AudioProcess.swift` (campo novo)
- Modify: `Sources/Wavern/AudioProcessController.swift:356-357, 383-391`
- Modify: `Sources/Wavern/AudioProcessController+Ducking.swift:43-44`

**Interfaces:**
- Produces: `AudioProcess.isUsingInput: Bool`, lido de `kAudioProcessPropertyIsRunningInput` em `makeProcess`.

**Mudanças:**
- Em `apply`, adicionar `listenProcess(kAudioProcessPropertyIsRunningInput, on:)`.
- Em `updateDucking`: `let active = processes.contains { $0.isUsingInput && isDucker($0) }`.
- `reapplyAllGains` continua pulando duckers sem tap. Os apps de chamada nunca recebem tap por causa do ducking.

- [ ] **Step 1:** Implementar e rodar o typecheck rápido.
- [ ] **Step 2:** Build real e instalar. Deixar o ducking em 30% e tocar música.
  - Abrir o Discord sem entrar em call → a música não abaixa.
  - Entrar numa call ou abrir o teste de microfone em Discord → Configurações → Voz → a música abaixa.
  - Sair → depois de cerca de 1 s, a música volta.
- [ ] **Step 3: Commit**
  ```bash
  git commit -am "fix(ducking): duck only while a call app is using the microphone"
  ```

---

### Task 7: Marca (ícone do app, glifo da barra de menu, kit de marca)

**Files:**
- Create: `scripts/make-icon.swift`, `Resources/AppIcon.icns`
- Create: `docs/brand/mark.svg`, `docs/brand/logo.svg`, `docs/brand/icon.png`, `docs/brand/README.md`
- Create: `Sources/Wavern/BrandGlyph.swift`
- Modify: `project.yml` (adicionar `Resources/AppIcon.icns` como resource do target Wavern), `Sources/Wavern/Info.plist` (`CFBundleIconFile` = `AppIcon`)

**Interfaces:**
- Produces: `enum BrandGlyph { static func menuBarImage(playing: Bool) -> NSImage }`. A imagem é template de 18×18 pt, desenhada com `NSImage(size:flipped:drawingHandler:)`. Ela traz três trilhos verticais e três botões de fader:
  - `playing == false`: os três botões na mesma altura baixa;
  - `playing == true`: os botões em alturas crescentes (onda), como no conceito 2.

**Desenho:** é o conceito 2 de `.superpowers/brainstorm/3425-1793408703/content/logo.html` (símbolo `g2`, com o glifo `m2` para a barra). Correções obrigatórias em relação ao rascunho:
- botões de fader **centrados** nos trilhos;
- a linha da onda passa pelo centro dos três botões.

Ícone:
- quadrado escuro arredondado no estilo de `~/Development/capta/CrispShot/Assets.xcassets/AppIcon.appiconset/icon_512x512@1x.png`, com gradiente `#2a2a33 → #121218 → #0b0b10` e borda branca a 0.12;
- trilhos brancos a 0.14;
- botões e linha da onda em gradiente `#D8B4FE → #C084FC → #8B3DFF`;
- brilho radial `#A855F7` a 0.55 atrás.

**Script:** o `make-icon.swift` segue a estrutura de `~/Development/estudos/monitor/scripts/make-icon.swift`: renderiza nos tamanhos do iconset, chama `iconutil` e grava também `docs/brand/icon.png` (1024).

**SVGs:** feitos à mão com a mesma geometria. `logo.svg` = símbolo + "wavern" em minúsculas, fonte do sistema 600.

**README:** no formato de `~/Development/estudos/monitor/docs/brand/README.md`. Traz a tabela de arquivos, a paleta da §4.1 do spec e a regra "wavern" (minúsculas no logo, "Wavern" no texto).

- [ ] **Step 1:** Escrever o `make-icon.swift`, rodar `swift scripts/make-icon.swift Resources/AppIcon.icns` (esperado: `ok Resources/AppIcon.icns`) e abrir `docs/brand/icon.png` para conferir.
- [ ] **Step 2:** Mostrar o `icon.png` em 1024 e em 32 px (`sips -Z 32`) para o dono aprovar antes de seguir. É a única aprovação visual intermediária do plano.
- [ ] **Step 3:** Criar os SVGs, o README e o `BrandGlyph.swift`. Ligar o ícone no `project.yml`/`Info.plist`. Rodar `xcodegen generate` e o build real.
- [ ] **Step 4:** Instalar e conferir no Finder: o `/Applications/Wavern.app` mostra o ícone novo (pode precisar de `touch /Applications/Wavern.app`).
- [ ] **Step 5: Commit**
  ```bash
  git add scripts/make-icon.swift Resources docs/brand Sources/Wavern/BrandGlyph.swift project.yml Sources/Wavern/Info.plist Wavern.xcodeproj
  git commit -m "feat(brand): Wavern app icon, menu bar glyph and brand kit"
  ```

---

### Task 8: Painel próprio, tema e fundo (infraestrutura do visual)

**Files:**
- Create: `Sources/Wavern/Theme.swift`, `Sources/Wavern/BrandSurface.swift`, `Sources/Wavern/StatusPanel.swift`
- Delete: `Sources/Wavern/VisualEffectBackground.swift`
- Modify: `Sources/Wavern/WavernApp.swift`

**Interfaces:**
- Consumes: `BrandGlyph.menuBarImage(playing:)` (Task 7).
- Produces:
  ```swift
  enum Theme {   // valores exatos de ~/Development/capta/CrispShot/Editor/ToolIsland.swift:17-40
      static let accentLight, accentDeep, accentGlow, record: Color
      static let icon, quiet, hover, pressed, divider: Color   // dinâmicas dark/light
      static let accentGradient: LinearGradient                  // accentLight → accentDeep, topLeading → bottomTrailing
      static let panelWidth: CGFloat = 300
      static let panelMaxHeight: CGFloat = 560
      static let cornerRadius: CGFloat = 14
  }
  struct BrandSurface: NSViewRepresentable   // porte de CrispShot/Editor/BrandBackdrop.swift (vibrancy + tinta 0.92 + 3 blobs 0.55; sólido com Reduce Transparency)
  @MainActor final class StatusPanel {
      init(controller: AudioProcessController, updateChecker: UpdateChecker)
      func toggle()
      private(set) var isOpen: Bool
  }
  ```

**`StatusPanel`:** é um porte de `CrispShot/App/MenuPanel.swift` (classe `MenuPanel`, linhas 107-207) e de `CrispShot/App/MenuBarController.swift`:
- `NSStatusItem` com `BrandGlyph.menuBarImage(playing: controller.isAnyPlaying)`. Atualiza via Combine em `controller.$processes`, só quando o booleano muda.
- Painel `[.borderless, .nonactivatingPanel]`, nível `.popUpMenu`, fundo clear, com sombra, 6 pt abaixo do item.
- Fecha ao clicar fora (monitor global de mouse) e com Esc.
- Animação de abertura: `spring(duration: 0.38, bounce: 0.22)`, escala 0.96→1 ancorada no topo, com fade. Com Reduce Motion, ease-out de 0.16 s.

**Regra de CPU (§3.6):**
- Em `show`: criar um `NSHostingView(rootView: MenuView().environmentObject(…))` novo e chamar `controller.beginLiveUpdates()`.
- Em `close`: depois da animação, `panel.contentView = nil` e `controller.endLiveUpdates()`.

Assim nenhuma `TimelineView`, marquee ou animação existe com o painel fechado.

**`WavernApp`:**
- Sai o `MenuBarExtra` e o hack de transparência (linhas 37-44).
- O `body` vira `Settings { EmptyView() }`, porque o app continua `LSUIElement`.
- `AppDelegate` cria e guarda o `StatusPanel` em `applicationDidFinishLaunching`.

**Cor:** o painel segue o modo claro/escuro do sistema, sem forçar esquema de cor.

- [ ] **Step 1:** Implementar `Theme`, `BrandSurface` e `StatusPanel` e trocar o `WavernApp`. Por enquanto, o `MenuView` atual só troca `VisualEffectBackground` por `BrandSurface` e a largura por `Theme.panelWidth`. Rodar `xcodegen generate` e o typecheck.
- [ ] **Step 2:** Build real e instalar. O clique no glifo abre o painel com animação. Clique fora e Esc fecham. O glifo muda entre parado e tocando.
- [ ] **Step 3 (CPU):** Fechar o painel com nada tocando, sem taps proativos (para isso, zere os volumes salvos ou use um perfil limpo) e esperar 10 s. Rodar `top -l 6 -s 10 -pid $(pgrep -x Wavern) -stats cpu | tail -5`. Esperado: média < 0.5%. Com música tocando e o painel fechado, rodar `sample $(pgrep -x Wavern) 3`. Esperado: nenhum frame de `AttributeGraph`, `RenderBox` ou `TimelineView`.
- [ ] **Step 4 (Review Focus 5):** Com o painel aberto, trocar a saída pelo seletor do sistema. Esperado: o painel continua aberto, a lista e o chip de dispositivo se atualizam e nenhuma linha fica presa em erro.
- [ ] **Step 5: Commit**
  ```bash
  git add -A Sources/Wavern Wavern.xcodeproj
  git commit -m "feat(ui): custom status panel with CrispShot theme; no rendering while closed"
  ```

---

### Task 9: Conteúdo do painel no visual CrispShot

**Files:**
- Create: `Sources/Wavern/Chip.swift`
- Modify: `Sources/Wavern/MenuView.swift` (reescrita), `Sources/Wavern/AudioProcessRow.swift`, `Sources/Wavern/VolumeSlider.swift`
- Delete: `Sources/Wavern/WaveformView.swift`. **Decisão de plano:** o destaque lilás e a opacidade já mostram quem está tocando; remover a forma de onda cumpre a §3.6 sem custo.

**Interfaces:**
- Consumes: `Theme`, `BrandSurface` (Task 8) e `isUncontrolled` (Task 5).
- Produces:
  ```swift
  struct Chip<Label: View>: View        // raio 8, padding 9/6, fonte 11, fill Theme.hover; hover → Theme.pressed, .easeOut(0.12)
  struct MenuChip<Content: View>: View  // Chip que abre um SwiftUI Menu (menuStyle .button, sem indicador)
  ```

**Layout:** é o mockup A de `.superpowers/brainstorm/3425-1793408703/content/visual-style.html`, com as medidas da §4.3 do spec.

1. **Cabeçalho:**
   - à esquerda, "Wavern" em 13 semibold;
   - à direita, um `MenuChip` com o SF Symbol do dispositivo (`OutputDevice.symbol`) e o nome, que lista `controller.outputDevices` e chama `selectOutputDevice`.
2. **Tile do master:** aparece só se `masterVolume != nil`. Tem `speaker.fill`, o `VolumeSlider` e a porcentagem em `.monospacedDigit()` com a cor `Theme.quiet`.
3. **"Now playing":** rótulo de 10.5 semibold em `quiet`, seguido dos tiles de `controller.playing`. A ordem é: o app em foco primeiro, depois os que estão tocando e por último os em linger.
   - **App em foco** = o último que começou a tocar, guardado no controller como `@Published private(set) var focusedID: AudioObjectID?` e atualizado em `noteActivity` quando `isPlaying`. Ou o tile sob o mouse.
   - **Tile em foco:**
     - fundo `Theme.accentGradient` a 0.95 com sombra `accentGlow` a 0.5, raio 9;
     - texto branco;
     - slider com preenchimento branco e trilho branco a 0.28;
     - subtítulo com título da faixa ou da aba (lógica atual de `AudioProcessRow`) em branco a 0.85.
   - **Demais tiles:** fundo `Theme.hover`.
   - **Mudo:** o tile inteiro a 0.55 de opacidade e o símbolo `speaker.slash.fill` em `Theme.record`.
   - **Em `uncontrolled`:** o aviso da Task 5.
   - **Sem nada tocando:** o estado vazio usa o `BrandGlyph` grande em `quiet` e o texto atual.
4. **Rodapé:** um divisor e uma linha de chips.
   - `MenuChip` de ducking com o rótulo `"Calls · 30%"` / `"Calls · Off"`, que lista `duckLevels`;
   - `Spacer`;
   - `MenuChip` ⚙︎ (`gearshape`), que contém:
     - o toggle "Media keys follow the playing app", com o aviso de Accessibility e "Open settings"/"Retry" quando `mediaKeysNeedPermission`;
     - o toggle "Launch at login";
     - "Update available" quando houver;
     - divisor e "Quit Wavern".
   - O aviso de permissão de áudio continua abaixo, em `quiet`.
5. **`VolumeSlider`:**
   - preenchimento `Theme.accentGradient`;
   - faixa de boost acima de 100% em `Theme.accentGlow` com a ponta mais clara (`#E9D5FF`), no lugar do laranja;
   - a marca de unidade continua;
   - novo parâmetro `onAccent: Bool` para a variante branca do tile em foco.
6. **Outros:**
   - nenhum `.accentColor`, `.secondary`, `.tertiary`, `Picker`, `Toggle(.switch/.checkbox)` ou `.borderless` visível no painel;
   - SF Symbols com `.symbolRenderingMode(.hierarchical)` e peso regular;
   - `ScrollView` quando o conteúdo passar de `Theme.panelMaxHeight`.

Funcionalidade que **precisa** sobreviver: as linhas de abas do navegador (`BrowserTabRow`), o onboarding da extensão (`ExtensionOnboardingSheet`), a artwork do Now Playing, o toggle de ducker por linha, o clique para ativar o app e o boost até 200%.

- [ ] **Step 1:** Implementar `Chip`/`MenuChip`, `VolumeSlider`, `AudioProcessRow` e `MenuView`, e apagar `WaveformView.swift`. Rodar `xcodegen generate`, o typecheck e `grep -nE "accentColor|\.secondary|\.tertiary|Picker\(|toggleStyle" Sources/Wavern/{MenuView,AudioProcessRow,VolumeSlider,Chip}.swift`. Esperado do grep: nenhuma linha.
- [ ] **Step 2:** Build real e instalar. Abrir o painel com Spotify e Chrome tocando, um app mudo e o modo escuro, e tirar uma captura com `screencapture -i`. Repetir no modo claro. Colocar as duas ao lado do mockup A e mostrar ao dono.
- [ ] **Step 3:** Checar a regressão de todos os recursos listados nos anti-objetivos do spec:
  - ducking;
  - perfis por dispositivo;
  - teclas de mídia;
  - volume por aba;
  - Now Playing;
  - seletor de saída;
  - volume master;
  - login item;
  - checagem de update.
- [ ] **Step 4: Commit**
  ```bash
  git add -A Sources/Wavern Wavern.xcodeproj
  git commit -m "feat(ui): CrispShot-style panel content with chips, focus tile and lilac sliders"
  ```

---

### Task 10: Verificação final

- [ ] **Step 1:** Rodar `bash scripts/check.sh`. Esperado: todos `ok`.
- [ ] **Step 2:** Repetir os passos manuais das Tasks 4 (2-6), 5 (3), 6 (2) e 8 (3-4) no build final instalado.
- [ ] **Step 3:** Usar o app normalmente por pelo menos 1 h, com música, chamada e fones Bluetooth. Depois rodar `log show --last 1h --predicate 'process == "Wavern"' | grep -iE "rebuild|watchdog|give up"`. Cada linha deve ter uma causa real correspondente. Nenhum `watchdog` deve se repetir em loop.
- [ ] **Step 4:** Atualizar a memória do projeto (`wavern-roadmap`) com o que foi feito.
