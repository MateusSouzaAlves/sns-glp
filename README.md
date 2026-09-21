# EmuOrbit Super Nintendo — fonte GPL

Este repositório contém somente a fonte correspondente do core de Super
Nintendo usado pelo EmuOrbit Advance. Não inclui código Java/Kotlin, interface,
recursos, ROMs, BIOS, telemetria, anúncios ou qualquer outro componente do
aplicativo.

## Conteúdo

- `core/bsnes`: submódulo do [bsnes](https://github.com/bsnes-emu/bsnes),
  fixado em `7d5aa1e656b9171524d01b1b22917197d8121cb4`.
- `patches/0001-emuorbit-android-libretro.patch`: ajustes reproduzíveis para
  compilar o alvo `bsnes/target-libretro` com Android NDK r29 e os pequenos
  ajustes do core usados pela integração Android: extensão de save `.sav`,
  flush explícito de save e falha segura quando um jogo não carrega.
- `scripts/build-android-arm64.ps1`: script mínimo para gerar
  `libretro.so` para `arm64-v8a` sem modificar o checkout do submódulo.

O bsnes é disponibilizado sob GPL-3.0-or-later. Os avisos e termos originais
estão em [`core/bsnes/LICENSE.txt`](core/bsnes/LICENSE.txt). Este repositório
preserva o commit exato e o patch aplicado à cópia temporária de compilação.

## Clonar e compilar

```powershell
git clone --recurse-submodules https://github.com/MateusSouzaAlves/sns-glp.git
cd sns-glp
.\scripts\build-android-arm64.ps1
```

O script localiza o Android NDK pelo `ANDROID_NDK_HOME`, `ANDROID_NDK_ROOT` ou
pelo SDK padrão do Windows. Para apontar outro executável:

```powershell
.\scripts\build-android-arm64.ps1 -NdkBuild 'C:\caminho\para\ndk-build.cmd'
```

O resultado é gravado em `artifacts/android/arm64-v8a/libretro.so`. Ele é o
core libretro genérico; o renomeio privado da biblioteca e a ponte JNI pertencem
ao aplicativo e não fazem parte deste repositório de fonte GPL.

## Reprodutibilidade

O script verifica o commit do submódulo e aplica o patch com `git apply --check`
antes do build. Ele usa um worktree temporário, `APP_PLATFORM=android-26` e LTO
desativado, reproduzindo o contrato de compilação do core sem alterar a fonte
original. Nenhum binário gerado deve ser versionado aqui.
