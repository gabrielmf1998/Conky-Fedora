# Conky Fedora

Painel de monitoramento em Conky para **Fedora Rawhide + KDE Plasma (Wayland)**, denso e
em inglês, com fonte bitmap pequena. Feito para caber inteiro numa tela 1080p sem cortar.

Cobre CPU (com barra por thread), GPU NVIDIA, memória, VRM/placa, armazenamento com modelo
real dos discos, bateria de headset sem fio e uma seção de rede detalhada.

```
fedora            Linux 7.3.0-0.rc0.260819gbd5f485f3f02.5.fc46 on x86_64
Fedora Linux 46                    up 1d 10h 21m            since 14:34
Tasks 450/0       Threads 1631     Pkgs 2995    Failed 0    KDE Wayland

CPU ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─
AMD Ryzen 7 9800X3D                                          gov epp
Usage    1%   ▓▓░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
Freq     5.38 GHz    Boost 5.46 GHz    Temp 50°C    Fans 1510/1500
Ctx/s    19214       Intr/s 7717       Power 37.3W  Load 0.12 0.93 0.98
[  gráfico de uso da CPU, gradiente roxo                             ]
00▓▓░ 01▓░░ 02▓▓░ 03░░░ 04▓░░ 05░░░ 06▓░░ 07░░░
08░░░ 09▓░░ 10░░░ 11▓▓░ 12░░░ 13▓░░ 14░░░ 15░░░
By CPU            PID       CPU%     MEM%      RES
...
```

## Requisitos

```bash
sudo dnf install conky ax86-terminus-ttf-fonts lm_sensors
```

Opcional, conforme o hardware: `nvidia-smi` (driver NVIDIA) para a seção GPU.

## Instalação

```bash
git clone <este-repo> && cd Conky-Fedora
./install.sh
```

O instalador copia a config para `~/.config/conky/pride/`, instala a regra udev do RAPL
(pede senha), cria o autostart do KDE e sobe o painel.

Para desinstalar: `./install.sh --remove`.

## Estrutura

| Caminho | O que é |
|---|---|
| `conky/pride.conf` | a config do painel (Lua, conky ≥ 1.10) |
| `conky/scripts/sys.sh` | coletor único com cache: GPU, headset, discos, contadores |
| `conky/scripts/w-*.sh` | wrappers de uma linha (ver [armadilhas](docs/03-armadilhas.md#3)) |
| `conky/60-rapl.rules` | libera os contadores de energia da CPU para o grupo `wheel` |
| `docs/` | como construir isso na mão, do zero |

## Documentação

1. **[Construindo do zero](docs/01-construindo-do-zero.md)** — o passo a passo, da janela
   vazia ao painel completo: sintaxe, alinhamento em pixels, barras, gráficos, e como
   medir se cabe na tela.
2. **[O que coletar e de onde](docs/02-o-que-coletar.md)** — catálogo das fontes de dado:
   o que o conky já sabe ler sozinho e o que exige script.
3. **[Armadilhas](docs/03-armadilhas.md)** — os problemas reais que apareceram montando
   isso, com o diagnóstico e o conserto de cada um. É a parte que economiza mais tempo.

## Este painel assume um hardware

Está calibrado para a máquina onde foi feito. Os pontos a trocar estão listados em
[docs/01](docs/01-construindo-do-zero.md#adaptando-para-outro-hardware):

- CPU AMD (sensor `k10temp`) com 16 threads
- GPU NVIDIA (via `nvidia-smi`)
- Super I/O `nct6799` (temperaturas de placa e RPM das fans)
- interface de rede `enp7s0`
- montagens `/`, `/boot`, `/mnt/samsung-980pro`, `/mnt/ssd-kingston`
- headset Corsair VOID (driver `hid-corsair-void`, kernel ≥ 6.13)

Nada disso é obrigatório: cada seção é independente e pode sair da config sem quebrar o
resto.

## Licença

MIT.
