# O que coletar e de onde

Catálogo das fontes de dado usadas neste painel. A pergunta que guia tudo: **o conky já
sabe ler isso sozinho, ou precisa de script?**

Objeto nativo é sempre melhor — não gasta processo. Só caia para `${execi}` quando o dado
não existir no conky ou exigir cálculo.

---

## CPU

| Dado | Como | Fonte real |
|---|---|---|
| uso total / por thread | `${cpu cpu0}`, `${cpu cpu1}`…`${cpu cpu16}` | `/proc/stat` |
| frequência | `${freq_g}` | `/proc/cpuinfo` |
| frequência máxima | `${execi 3600 ...cpuinfo_max_freq}` | `/sys/devices/system/cpu/cpu0/cpufreq/` |
| driver de escalonamento | idem, `scaling_driver` | mesma pasta |
| load average | `${loadavg 1} ${loadavg 2} ${loadavg 3}` | `/proc/loadavg` |
| processos / threads | `${processes}`, `${running_processes}`, `${threads}` | `/proc/loadavg`, `/proc` |
| temperatura | `${hwmon k10temp temp 1}` | `/sys/class/hwmon/*/temp1_input` |
| **consumo em watts** | script (delta de energia) | `/sys/class/powercap/intel-rapl:0/energy_uj` |
| trocas de contexto / interrupções | script (delta) | `/proc/stat`, linhas `ctxt` e `intr` |

`${cpu cpu0}` é o **total**; `cpu1` em diante são as threads individuais. Um 8 núcleos com
SMT tem 16 threads, então vai de `cpu1` a `cpu16`.

Atenção em `${hwmon}`: **aceita o nome do chip**, não só o índice. Use sempre o nome
(`k10temp`, `nct6799`) — o índice muda entre boots.

### Watts da CPU (RAPL)

`energy_uj` é um contador **acumulado em microjoules**. Potência = delta de energia
dividido pelo delta de tempo:

```
W = ΔµJ / (Δms × 1000)
```

Dois detalhes que quebram implementações ingênuas:

1. o contador **dá a volta** em `max_energy_range_uj` (aqui, 65,5 kJ ≈ 11 min sob carga).
   Se o delta der negativo, some o máximo;
2. os arquivos são **root-only** por padrão. Veja
   [armadilhas #6](03-armadilhas.md#6-rapl-é-root-only-e-o-contador-dá-a-volta).

Há dois domínios: `intel-rapl:0` (**package**, o processador inteiro) e `intel-rapl:0:0`
(**core**). Em Zen o domínio `core` sub-reporta muito — media 0,9 W enquanto o package
marcava 38 W. Use o package.

## Memória

Tudo nativo, de `/proc/meminfo`:

```
${mem} ${memmax} ${memperc} ${membar}      em uso
${memavail}                                 disponível de verdade (≠ free)
${cached} ${buffers}
${swap} ${swapmax} ${swapperc} ${swapbar}
```

Campos que o conky não expõe e valem a pena, via `awk` no `/proc/meminfo`:

- **`Dirty`** — páginas sujas esperando ir para o disco. Se dispara, escrita travada.
- **`Slab`** — memória de estruturas do kernel. Cresce em máquina com muito I/O.
- **`Shmem`** — memória compartilhada, inclui `/dev/shm` e tmpfs.

Taxa de paginação: delta de `pgpgin`/`pgpgout` em `/proc/vmstat` (valores em páginas de
4 KiB → multiplique por 4096 para ter bytes).

## GPU NVIDIA

Nada é nativo (a menos que o conky tenha sido compilado com suporte NVIDIA, o que não é o
caso no pacote do Fedora). Tudo vem de **uma** chamada de `nvidia-smi`, com o resultado
cacheado:

```bash
nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total,\
clocks.sm,fan.speed,power.draw,clocks.mem,pcie.link.gen.current,\
pcie.link.width.current,power.limit,utilization.memory,pstate,\
utilization.encoder,utilization.decoder --format=csv,noheader,nounits
```

Quem está usando a GPU:

```bash
nvidia-smi --query-compute-apps=name,used_memory --format=csv,noheader,nounits
```

Chamar `nvidia-smi` custa ~50-80ms. **Nunca chame uma vez por campo** — colete tudo de uma
vez e sirva de um cache.

## Armazenamento

| Dado | Como |
|---|---|
| uso, tamanho, livre, % | nativos: `${fs_used}` `${fs_size}` `${fs_free}` `${fs_used_perc}` `${fs_bar}` |
| tipo do sistema de arquivos | `findmnt -no FSTYPE <mount>` |
| uso de inodes | `df --output=ipcent <mount>` (btrfs reporta `-`, é normal) |
| **modelo do disco** | `lsblk -dno MODEL /dev/<dev>` |
| temperatura | `/sys/block/<dev>/device/hwmon*/temp1_input` |

O pulo do gato é **resolver o ponto de montagem até o disco físico em tempo de execução**:

```bash
src=$(findmnt -no SOURCE --target "$mnt" | sed 's/\[.*\]//')   # tira [/subvol] do btrfs
dev=$(lsblk -no PKNAME "$src" | head -1)                       # partição -> disco pai
model=$(lsblk -dno MODEL "/dev/$dev")
```

Por que não hardcodar: **o número do NVMe muda entre boots**. Ver
[armadilhas #2](03-armadilhas.md#2-o-número-do-nvme-muda-entre-boots).

E use `lsblk` para o modelo, **não o sysfs**: `/sys/block/sda/device/model` corta em 16
caracteres (`KINGSTON SA400S3` em vez de `KINGSTON SA400S37960G`).

## Rede

| Dado | Como |
|---|---|
| endereço | `${addr enp7s0}` |
| velocidade instantânea | `${downspeed}` / `${upspeed}` |
| total acumulado | `${totaldown}` / `${totalup}` |
| gráficos | `${downspeedgraph}` / `${upspeedgraph}` |
| conexões abertas | `${tcp_portmon <porta_ini> <porta_fim> count}` |
| host/serviço/porta remotos | `${tcp_portmon ... rhost N}`, `rservice`, `rport`, `lport` |
| velocidade do link, MTU | `/sys/class/net/<if>/speed`, `/mtu` |
| pacotes, erros, descartes | `/sys/class/net/<if>/statistics/*` |
| gateway | `ip route show default \| awk '{print $3}'` |
| DNS | `resolvectl dns <if>` |
| estados TCP | `ss -tan \| awk 'NR>1{c[$1]++} END{...}'` |

O `tcp_portmon` separa entrada de saída pela faixa de portas: portas efêmeras no Linux são
**32768-60999**, então conexões de saída caem nessa faixa e as de entrada abaixo dela.
Exige conky compilado com `portmon` (o pacote do Fedora tem).

## Placa-mãe, VRM e fans

Tudo pelo Super I/O via `hwmon`. Descubra o seu com `sensors`:

```
${hwmon nct6799 temp 1}    SYSTIN   — temperatura da placa
${hwmon nct6799 temp 2}    CPUTIN   — do socket
${hwmon nct6799 fan 2}              — RPM do canal 2
${hwmon nct6799 vol 0}     VCORE    — tensão do núcleo
```

**Sobre VRM:** muitas placas simplesmente **não expõem sensor de VRM**. Nesta ASRock B650M
os canais `AUXTIN0-5` leem 10-22°C (abaixo do ambiente = desconectados) e o `AUXTIN5` crava
108°C fixo, que é lixo de canal sem nada ligado. Antes de mostrar um número como "VRM",
confira se ele reage à carga — senão você está publicando ficção.

Tensão do SoC em AMD sai pelo driver da iGPU:

```bash
sensors -u amdgpu-pci-0f00 | awk '/in1_input/{print $2}'    # VSOC
sensors -u amdgpu-pci-0f00 | awk '/temp1_input/{print $2}'  # temp do IOD
```

## Headset sem fio (Corsair VOID)

Driver `hid-corsair-void`, no kernel desde a 6.13. Expõe uma `power_supply`:

```
/sys/class/power_supply/corsair-void-*-battery/capacity
/sys/class/power_supply/corsair-void-*-battery/status
```

Use **glob**, nunca o caminho fixo: o índice muda a cada reconexão do dongle.

E não confie no valor enquanto carrega — o medidor é por tensão. Ver
[armadilhas #7](03-armadilhas.md#7-a-bateria-do-headset-mente-enquanto-carrega).

## Sistema

```
${nodename} ${kernel} ${machine} ${uptime}
```

Extras úteis: `uptime -s` (hora do boot), `rpm -qa | wc -l` (pacotes instalados),
`systemctl --failed --no-legend | wc -l` (unidades falhadas — ótimo alarme silencioso).

## Processos

Nativo, e mais barato que chamar `ps`:

```
${top name N} ${top pid N} ${top cpu N} ${top mem N} ${top mem_res N}
${top_mem name N} ...        mesma coisa, ordenado por memória
```

Campos válidos: `name, cpu, pid, mem, time, mem_res, mem_vsize, io_read, io_write,
io_perc`. Qualquer outro derruba a config com *"invalid type arg for top"*.

`mem_res` (residente, em bytes legíveis) costuma ser mais informativo que `mem` (%).

O nome vem do `comm` do kernel, **limitado a 15 caracteres** — é por isso que aparece
`Isolated Web Co` em vez de `Isolated Web Content`. Não é bug do conky.
