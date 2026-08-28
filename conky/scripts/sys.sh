#!/bin/bash
# Coletor do painel. Duas cadências:
#   MAP  (60s) — resolução mount -> device -> modelo (findmnt/lsblk são caros)
#   FAST (2s)  — GPU, headset, IO, contadores do kernel, TCP
# Uso: sys.sh <chave>

CACHE="/tmp/.conky-pride.$UID"
PREV="/tmp/.conky-pride-prev.$UID"
MAP="/tmp/.conky-pride-map.$UID"
# estado do headset persiste entre reboots: /tmp seria apagado
HS_STATE="$HOME/.local/state/conky-pride/headset"
TTL=2
MAP_TTL=60

MOUNTS=( "root:/" "boot:/boot" "p980:/mnt/samsung-980pro" "kingston:/mnt/ssd-kingston" )

build_map() {
    local out="" entry key mnt src dev model
    for entry in "${MOUNTS[@]}"; do
        key=${entry%%:*}; mnt=${entry#*:}
        src=$(findmnt -no SOURCE --target "$mnt" 2>/dev/null | sed 's/\[.*\]//')
        [[ -n $src ]] || continue
        dev=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1)
        [[ -n $dev ]] || dev=$(basename "$src")
        # lsblk traz o modelo inteiro; o sysfs corta em 16 chars no SATA
        model=$(lsblk -dno MODEL "/dev/$dev" 2>/dev/null | sed 's/  */ /g; s/^ *//; s/ *$//')
        out+="$key $dev ${model:-$dev}"$'\n'
    done
    printf '%s' "$out" > "$MAP.tmp" && mv -f "$MAP.tmp" "$MAP"
}

refresh() {
    local out="" now dt key dev model
    now=$(date +%s%3N)

    # ── GPU
    local g
    g=$(nvidia-smi --query-gpu=temperature.gpu,utilization.gpu,memory.used,memory.total,clocks.sm,fan.speed,power.draw,clocks.mem,pcie.link.gen.current,pcie.link.width.current,power.limit,utilization.memory,pstate,utilization.encoder,utilization.decoder \
        --format=csv,noheader,nounits 2>/dev/null)
    if [[ -n $g ]]; then
        IFS=', ' read -r gt gu gvu gvt gc gf gp gmc gpg gpw gpl gmu gps ge gd <<<"$g"
        out+="gpu_temp=$gt"$'\n'"gpu_util=$gu"$'\n'"gpu_vused=$gvu"$'\n'"gpu_vtotal=$gvt"$'\n'
        out+="gpu_clock=$gc"$'\n'"gpu_fan=$gf"$'\n'"gpu_power=$gp"$'\n'"gpu_memclock=$gmc"$'\n'
        out+="gpu_pcie=${gpg}.0 x${gpw}"$'\n'"gpu_plimit=${gpl%%.*}"$'\n'"gpu_memutil=$gmu"$'\n'
        out+="gpu_pstate=$gps"$'\n'"gpu_enc=$ge"$'\n'"gpu_dec=$gd"$'\n'
        out+="gpu_vperc=$(( gvu * 100 / (gvt > 0 ? gvt : 1) ))"$'\n'
        out+="gpu_pperc=$(awk -v d="$gp" -v l="$gpl" 'BEGIN{printf "%d", (l>0? d*100/l : 0)}')"$'\n'
    fi

    # maior consumidor de VRAM
    local topapp
    topapp=$(nvidia-smi --query-compute-apps=name,used_memory --format=csv,noheader,nounits 2>/dev/null |
             sort -t, -k2 -nr | head -1)
    if [[ -n $topapp ]]; then
        out+="gpu_app=$(basename "${topapp%%,*}")"$'\n'"gpu_appmem=$(echo "${topapp##*,}" | tr -d ' ')"$'\n'
    fi

    # ── headset Corsair VOID
    #
    # O medidor do headset é por TENSÃO, não conta carga. Ao ligar o cabo, a
    # tensão nos terminais sobe na hora e a leitura dispara: com a bateria
    # zerada ele reporta ~90%. Não existe offset constante que corrija isso —
    # o comentário do driver ("~54 higher than reality when charging, capped
    # at 100") é uma média que erra feio nos extremos. Medido em 26/08: bateria
    # morta, recém-conectada, driver reportando 88..92 oscilando.
    #
    # Portanto: enquanto carrega, a leitura é DESCARTADA e o painel segura o
    # último valor confiável (o último lido descarregando e já assentado).
    local b cap st now_s hs_state="" hs_disp="" hs_num=0
    local last_good="" last_charge=0
    now_s=$(date +%s)
    [[ -f $HS_STATE ]] && . "$HS_STATE"

    for b in /sys/class/power_supply/corsair-void-*-battery; do
        [[ -r $b/capacity ]] || continue
        cap=$(<"$b/capacity"); st=$(<"$b/status")
        (( cap > 100 )) && cap=100
        (( cap < 0 )) && cap=0

        case $st in
            Charging)
                last_charge=$now_s
                hs_state="charging"
                if [[ -n $last_good ]]; then hs_num=$last_good; hs_disp="~${last_good}%"
                else hs_num=0; hs_disp="--"; fi
                ;;
            Full)
                hs_state="full"; hs_num=100; hs_disp="100%"; last_good=100
                ;;
            *)  # Discharging: a tensão leva ~2min pra assentar depois do cabo sair
                if (( now_s - last_charge < 150 )); then
                    hs_state="settling"
                    if [[ -n $last_good ]]; then hs_num=$last_good; hs_disp="~${last_good}%"
                    else hs_num=$cap; hs_disp="~${cap}%"; fi
                else
                    hs_state="discharging"; hs_num=$cap; hs_disp="${cap}%"; last_good=$cap
                fi
                ;;
        esac

        out+="hs_level=$hs_num"$'\n'"hs_display=$hs_disp"$'\n'"hs_status=$hs_state"$'\n'"hs_raw=$cap"$'\n'
        printf 'last_good=%s\nlast_charge=%s\n' "${last_good:-}" "$last_charge" > "$HS_STATE.tmp" &&
            mv -f "$HS_STATE.tmp" "$HS_STATE"
        break
    done

    # ── discos: usa o mapa cacheado, só lê temperatura e diskstats
    local stats hw line r w busy
    declare -A curr
    stats=$(</proc/diskstats)
    while read -r key dev model; do
        [[ -n $key ]] || continue
        out+="dev_$key=$dev"$'\n'"model_$key=$model"$'\n'
        for hw in /sys/block/$dev/device/hwmon*/temp1_input; do
            [[ -r $hw ]] && out+="temp_$key=$(( $(<"$hw") / 1000 ))"$'\n'
        done
        line=$(grep -m1 " $dev " <<<"$stats")
        if [[ -n $line ]]; then
            read -r _ _ _ _ _ r _ _ _ w _ _ busy _ <<<"$line"
            curr[$key]="$((r * 512)) $((w * 512)) ${busy:-0}"
            out+="tr_$key=$((r * 512))"$'\n'"tw_$key=$((w * 512))"$'\n'
        fi
    done < "$MAP"

    # ── consumo da CPU via RAPL (µJ acumulados; dá a volta em max_energy_range_uj)
    local rapl_pkg=0 rapl_core=0 rapl_max=0
    if [[ -r /sys/class/powercap/intel-rapl:0/energy_uj ]]; then
        rapl_pkg=$(</sys/class/powercap/intel-rapl:0/energy_uj)
        rapl_max=$(</sys/class/powercap/intel-rapl:0/max_energy_range_uj)
        [[ -r /sys/class/powercap/intel-rapl:0:0/energy_uj ]] &&
            rapl_core=$(</sys/class/powercap/intel-rapl:0:0/energy_uj)
    fi

    # ── contadores do kernel
    local ctxt intr pgin pgout
    ctxt=$(awk '/^ctxt/{print $2}' /proc/stat)
    intr=$(awk '/^intr/{print $2}' /proc/stat)
    read -r pgin pgout < <(awk '/^pgpgin/{i=$2} /^pgpgout/{o=$2} END{print i, o}' /proc/vmstat)

    # ── deltas contra o snapshot anterior
    local have_prev=0
    if [[ -f $PREV ]]; then
        have_prev=1
        local pnow; pnow=$(head -1 "$PREV")
        dt=$(( now - pnow ))
        if (( dt > 200 )); then
            local pk pr pw pb cr cw cb
            while read -r pk pr pw pb; do
                case $pk in
                    __ctxt) out+="ctxt_s=$(( (ctxt - pr) * 1000 / dt ))"$'\n' ;;
                    __intr) out+="intr_s=$(( (intr - pr) * 1000 / dt ))"$'\n' ;;
                    __pg)   out+="pgin_s=$(( (pgin - pr) * 512000 / dt ))"$'\n'
                            out+="pgout_s=$(( (pgout - pw) * 512000 / dt ))"$'\n' ;;
                    __rapl)
                        local de
                        if (( rapl_pkg > 0 && pr > 0 )); then
                            de=$(( rapl_pkg - pr )); (( de < 0 )) && de=$(( de + rapl_max ))
                            out+="cpu_power=$(awk -v e="$de" -v t="$dt" 'BEGIN{printf "%.1f", e/(t*1000)}')"$'\n'
                        fi
                        if (( rapl_core > 0 && pw > 0 )); then
                            de=$(( rapl_core - pw )); (( de < 0 )) && de=$(( de + rapl_max ))
                            out+="cpu_power_core=$(awk -v e="$de" -v t="$dt" 'BEGIN{printf "%.1f", e/(t*1000)}')"$'\n'
                        fi
                        ;;
                    *)
                        [[ -n ${curr[$pk]} ]] || continue
                        read -r cr cw cb <<<"${curr[$pk]}"
                        out+="r_$pk=$(( (cr - pr) * 1000 / dt ))"$'\n'
                        out+="w_$pk=$(( (cw - pw) * 1000 / dt ))"$'\n'
                        out+="busy_$pk=$(( (cb - pb) * 100 / dt ))"$'\n'
                        ;;
                esac
            done < <(tail -n +2 "$PREV")
        fi
    fi

    # ── rede e serviços
    out+=$(ss -tan 2>/dev/null | awk 'NR>1{c[$1]++} END{
        printf "tcp_estab=%d\ntcp_listen=%d\ntcp_tw=%d\n", c["ESTAB"], c["LISTEN"], c["TIME-WAIT"]}')$'\n'
    out+="failed_units=$(systemctl --failed --no-legend 2>/dev/null | wc -l)"$'\n'

    # Só regrava o snapshot quando o intervalo foi suficiente. Sem isso, dois
    # refreshes seguidos zeram a base e o delta nunca aparece.
    if (( ! ${have_prev:-0} )) || (( ${dt:-0} > 200 )); then
    {   echo "$now"
        echo "__ctxt $ctxt 0 0"
        echo "__intr $intr 0 0"
        echo "__pg $pgin $pgout 0"
        echo "__rapl $rapl_pkg $rapl_core 0"
        for key in "${!curr[@]}"; do echo "$key ${curr[$key]}"; done
    } > "$PREV.tmp" && mv -f "$PREV.tmp" "$PREV"
    fi
    printf '%s' "$out" > "$CACHE.tmp" && mv -f "$CACHE.tmp" "$CACHE"
}

mage=99
[[ -f $MAP ]] && mage=$(( $(date +%s) - $(stat -c %Y "$MAP") ))
(( mage >= MAP_TTL )) && build_map

age=99
[[ -f $CACHE ]] && age=$(( $(date +%s) - $(stat -c %Y "$CACHE") ))
if (( age >= TTL )); then
    # o conky dispara ~30 chamadas de uma vez; sem flock elas colidem no refresh
    exec 9>"$CACHE.lock"
    if flock -n 9; then
        age=99
        [[ -f $CACHE ]] && age=$(( $(date +%s) - $(stat -c %Y "$CACHE") ))
        (( age >= TTL )) && refresh
        flock -u 9
    fi
fi

[[ -f $CACHE ]] || { echo "-"; exit 0; }
v=$(grep -m1 "^$1=" "$CACHE" 2>/dev/null)
v=${v#*=}

# chaves de bytes saem cruas -> humanizar
if [[ $1 == r_* || $1 == w_* || $1 == tr_* || $1 == tw_* || $1 == pgin_s || $1 == pgout_s ]]; then
    n=${v:-0}
    if   (( n >= 1099511627776 )); then awk -v b="$n" 'BEGIN{printf "%.1fT", b/1099511627776}'
    elif (( n >= 1073741824 ));    then awk -v b="$n" 'BEGIN{printf "%.1fG", b/1073741824}'
    elif (( n >= 1048576 ));       then awk -v b="$n" 'BEGIN{printf "%.1fM", b/1048576}'
    elif (( n >= 1024 ));          then awk -v b="$n" 'BEGIN{printf "%.0fK", b/1024}'
    else echo "${n}B"; fi
    exit 0
fi
echo "$v"
