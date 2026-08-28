# Armadilhas

Os problemas reais que apareceram montando este painel. Cada um custou tempo de
diagnóstico; estão aqui com o sintoma, a causa e o conserto.

---

## 1. O índice do `hwmon` muda entre boots

**Sintoma:** a temperatura da CPU aparece certa hoje e mostra o valor de outro chip
amanhã.

**Causa:** `/sys/class/hwmon/hwmon0`, `hwmon1`… são numerados na ordem em que os drivers
carregam, que não é estável. O `nct6799` foi `hwmon4` num boot e `hwmon0` no seguinte.

**Conserto:** o `${hwmon}` do conky aceita o **nome do chip**:

```
${hwmon k10temp temp 1}      em vez de   ${hwmon 5 temp 1}
```

Em script, varra procurando pelo nome:

```bash
for h in /sys/class/hwmon/*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "k10temp" ] && echo "$h/temp1_input"
done
```

## 2. O número do NVMe muda entre boots

**Sintoma:** o painel mostra o modelo errado no disco errado.

**Causa:** a mesma. O Samsung 980 PRO era `nvme1n1` num boot e virou `nvme0n1` no seguinte
— e o disco de sistema fez o caminho inverso.

**Conserto:** nunca hardcode o device. Resolva a partir do **ponto de montagem**, que é
estável, toda vez que o script rodar:

```bash
src=$(findmnt -no SOURCE --target /mnt/disco | sed 's/\[.*\]//')
dev=$(lsblk -no PKNAME "$src" | head -1)
```

O `sed` tira o sufixo `[/subvol]` que o btrfs coloca no SOURCE — sem ele o `lsblk`
recebe `/dev/nvme1n1p3[/root]` e falha.

Cuidado extra: pegue o modelo com `lsblk -dno MODEL`, porque o
`/sys/block/*/device/model` **corta em 16 caracteres** nos discos SATA.

## 3. `execbar` e `execgraph` não aceitam comando com argumento

**Sintoma:** a config nem carrega, com erros do tipo
`can't parse color 'util': invalid hex value`.

**Causa:** o parser lê o comando como um token só e tenta interpretar o argumento seguinte
como tamanho ou cor.

```
${execigraph 2 ~/scripts/sys.sh util 30,400 000020 ffa500}   ERRADO
```

**Conserto:** um wrapper de uma linha, sem argumento:

```bash
#!/bin/sh
exec "$HOME/.config/conky/pride/scripts/sys.sh" gpu_util
```

```
${execigraph 2 ~/scripts/w-gpu_util.sh 30,400 000020 ffa500}   CERTO
```

`${execibar}` aceita o tamanho **antes** do comando (`${execibar 2 7,160 cmd}`), e nesse
caso o comando pode ter argumento. Mas por consistência, use wrapper nos dois.

## 4. O conky chama seu script dezenas de vezes por ciclo

**Sintoma:** deltas calculados no script (taxa por segundo) saem vazios ou absurdos.

**Causa:** este painel tem ~30 `${execi}` apontando para o mesmo script. O conky dispara
todos praticamente juntos. Vários passam pela verificação de idade do cache ao mesmo
tempo, todos entram no refresh, e cada um **reescreve o snapshot anterior**. O último a
escrever deixa uma base com intervalo ~0, e o delta seguinte não tem de onde sair.

**Conserto: duas coisas juntas.**

```bash
# 1) só um refresh por vez
exec 9>"$CACHE.lock"
if flock -n 9; then
    # revalidar a idade DENTRO da trava
    (( age >= TTL )) && refresh
    flock -u 9
fi

# 2) só regravar o snapshot quando o intervalo foi útil
if (( ! have_prev )) || (( dt > 200 )); then
    ... > "$PREV"
fi
```

Sem a segunda parte a trava sozinha não resolve.

E separe o que é caro: a resolução `findmnt`/`lsblk` mudou para um cache próprio de 60s,
enquanto o resto atualiza a cada 2s. O script fica em ~3ms com o cache quente.

## 5. Verificar se o painel cabe na tela

**Sintoma:** o rodapé some.

**Causa:** o conky dimensiona a janela pelo conteúdo. Passando da altura da tela, ele
encosta no topo e o resto fica fora.

**Conserto:** medir de verdade, não no olho:

```bash
DISPLAY=:0 xdotool search --class Conky | while read id; do
    xdotool getwindowgeometry $id
done
```

Faça isso toda vez que adicionar uma seção.

## 6. RAPL é root-only, e o contador dá a volta

**Sintoma:** `cat /sys/class/powercap/intel-rapl:0/energy_uj` dá *Permission denied*.

**Causa:** os contadores de energia foram fechados para não-root por causa do
**PLATYPUS (CVE-2020-8694)** — leitura de energia em alta resolução funciona como canal
lateral para extrair chaves de criptografia.

**Conserto:** regra udev liberando para um grupo, **não para o mundo**:

```
SUBSYSTEM=="powercap", ACTION=="add", \
  RUN+="/usr/bin/chgrp -R wheel /sys%p", \
  RUN+="/usr/bin/chmod -R g+rX /sys%p"
```

Depois `udevadm control --reload-rules` e aplique uma vez à mão nos devices já criados,
porque a regra só dispara em `add`.

**Segunda armadilha:** o contador **dá a volta** em `max_energy_range_uj` — aqui 65,5 kJ,
o que sob carga acontece a cada ~11 minutos. Sem tratar, você vê picos absurdos:

```bash
delta=$(( atual - anterior ))
(( delta < 0 )) && delta=$(( delta + max_energy_range_uj ))
```

## 7. A bateria do headset mente enquanto carrega

**Sintoma:** o headset desliga por bateria zerada, você liga o cabo, e o painel mostra
90%.

**Causa:** o medidor do Corsair VOID é **por tensão**, não conta carga. Ligou o cabo, a
tensão nos terminais sobe na hora e a leitura dispara. Medido: bateria morta reportando
88..93% oscilando.

O comentário do próprio driver diz *"Seems to report ~54 higher than reality when
charging. Capped at 100"* — mas isso é uma média que **erra feio nos extremos**, e o driver
não aplica correção nenhuma (`battery_data->capacity = raw_battery_capacity`). Subtrair 54
de 88 dá 34% numa bateria vazia.

**Conserto:** não existe offset que corrija. Descarte a leitura enquanto carrega e
**segure o último valor confiável**:

- `Charging` → mostra o último valor bom, marcado com `~`
- `Discharging` nos primeiros ~150s após tirar o cabo → ainda segura (a tensão leva uns
  2 minutos para assentar)
- `Discharging` assentado → aí sim usa a leitura, e grava como último valor bom
- `Full` → 100%

Guarde esse estado **fora do `/tmp`** (ex.: `~/.local/state/`), para sobreviver a reboot.

## 8. `/proc/diskstats` pode simplesmente não contar

**Sintoma:** taxa de leitura/escrita sempre 0B/s, em qualquer ferramenta.

**Causa:** no kernel `7.3.0-0.rc0` desta máquina a contabilidade de I/O de bloco está
quebrada. Teste decisivo:

```bash
grep " nvme0n1 " /proc/diskstats
dd if=/dev/zero of=/ponto/de/montagem/teste bs=1M count=64 oflag=direct
sync
grep " nvme0n1 " /proc/diskstats     # não se moveu
```

Nenhum device passava de ~10 leituras desde o boot, e as partições estavam zeradas. **Não
era multipath** (`nvme_core.multipath=Y` está ligado, mas não existe nenhum device de path
`nvmeXcYnZ`).

**Consequência:** conky, `iostat`, `btop`, `atop` — todos leem a mesma fonte, todos
mostram zero. Não adianta trocar de ferramenta.

**Conserto:** nenhum em espaço de usuário. As alternativas (`nvme smart-log`, `smartctl`)
exigem root. Este painel mostra modelo, temperatura, uso e inodes em vez de R/W. Vale
retestar depois de trocar de kernel — cheira a regressão de release candidate.

## 9. Nomes de campo do `${top}`

**Sintoma:** `invalid type arg for top` e a config não carrega.

**Causa:** inventar campo. Não existe `${top threads N}` nem `${top_time N}`.

**Válidos:** `name, cpu, pid, mem, time, mem_res, mem_vsize, io_read, io_write, io_perc`.

## 10. Opções de janela que foram removidas

`own_window_transparent` e `own_window_argb_visual` **não existem mais** no conky 1.24 —
geram aviso e são ignoradas. Hoje é só `own_window_colour` com canal alfa
(`#AARRGGBB`).

## 11. Entropia não é mais métrica

`${entropy_avail}/${entropy_poolsize}` fica cravado em **256/256** em qualquer kernel
moderno. O pool virou 256 bits fixos e o CSPRNG (ChaCha20) nunca mais bloqueia depois de
semeado no boot. Em 2009 fazia sentido monitorar; hoje é decoração.

## 12. `console.log` sumindo, e outras miudezas

- Em conky, para depurar a saída de texto rapidamente, use o modo console
  (`out_to_console = true, total_run_times = 2`) em vez de abrir a janela.
- O aviso `invalid CPU number '(null)', falling back to CPU 1` na inicialização é
  inofensivo e aparece mesmo em configs sem nenhum objeto de CPU.
- Com fundo transparente, **ligue `draw_shades`** ou o texto some em papel de parede
  claro.
