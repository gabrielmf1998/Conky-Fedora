# Construindo do zero

Este documento ensina a chegar no painel na mão, decisão por decisão. Não é "cole esta
config": é o raciocínio, para você conseguir mudar qualquer coisa depois.

---

## 1. Conky no Wayland

O conky é um programa **X11**. No KDE Plasma sobre Wayland ele roda via **XWayland**, e
isso funciona bem — mas a janela precisa ser configurada certo, senão ela flutua por cima
dos aplicativos ou some atrás do papel de parede.

```lua
own_window = true,
own_window_type = 'normal',
own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
own_window_colour = '#00000000',   -- #AARRGGBB: alfa 00 = transparente
```

- `own_window_type = 'desktop'` costuma sumir atrás do desktop do plasmashell. Use
  `normal` + a dica `below`.
- `below` põe a janela abaixo das janelas normais, mas **acima** do papel de parede.
- `sticky` faz aparecer em todos os desktops virtuais.
- `skip_taskbar,skip_pager` tira da barra de tarefas e do alternador.

**`own_window_transparent` e `own_window_argb_visual` foram removidos** do conky 1.24.
Hoje a transparência é o canal alfa de `own_window_colour`: `'#00000000'` transparente,
`'#ff000000'` preto sólido, `'#99000000'` meio-termo.

Com fundo transparente, ligue a sombra do texto ou ele some em papel de parede claro:

```lua
draw_shades = true,
default_shade_color = '000000',
```

## 2. O esqueleto da config

Desde o conky 1.10 a config é **Lua**, não o formato antigo de `chave valor`:

```lua
conky.config = {
    -- opções aqui
}

conky.text = [[
   o conteúdo aqui, com ${objetos}
]]
```

Rodar sem instalar nada: `conky -c ./pride.conf`. Para testar só a saída de texto, sem
abrir janela, use o modo console — é muito mais rápido para iterar:

```lua
out_to_x = false, out_to_console = true, total_run_times = 2,
```

## 3. A fonte

Fonte **monoespaçada e bitmap** é o que dá o visual e, mais importante, torna o
alinhamento previsível. Aqui é a Terminus:

```lua
font = 'Terminus (TTF):pixelsize=11',
```

Use **`pixelsize`, não `size`**. `size` é em pontos e depende do DPI, então o mesmo número
rende alturas diferentes em máquinas diferentes. `pixelsize` é exato.

Regra prática da Terminus: **a largura de cada caractere é metade do `pixelsize`**. Com
`pixelsize=11`, cada caractere ocupa ~5,5px. Isso é o que permite calcular colunas.

Trocar de tamanho no meio do texto:

```
${font Terminus (TTF):bold:pixelsize=12}TÍTULO${font}
```

`${font}` sem argumento volta para a fonte padrão.

## 4. Alinhamento: o problema central

Um painel denso é 90% alinhamento. Existem três ferramentas:

| Objeto | O que faz | Quando usar |
|---|---|---|
| `${goto N}` | vai para o pixel N, contado da **borda da janela** | colunas fixas |
| `${alignr}` | alinha o resto da linha à direita | último item da linha |
| espaços literais | funcionam por ser fonte monoespaçada | tabelas simples |

**Cuidado com `${alignr}`:** ele empurra o resto da linha para a direita. Se um item com
`${goto}` antes dele for longo demais, os dois se sobrepõem e o texto vira lixo. Aconteceu
neste painel: `Power 39.8W` no `goto 290` colidiu com o `Load 0.22 1.05 1.02` alinhado à
direita, e saiu `Power 39.8Wad 0.22 1.05 1.02`.

A conta para evitar: com a janela de 448px e margem interna de 10, a área útil vai de 10 a
438. Um texto alinhado à direita com N caracteres **começa** em `438 - N*5.5`. O item
anterior tem que terminar antes disso.

```
"Load 0.12 0.93 0.98" = 19 chars × 5,5 = 104px  ->  começa em 438-104 = 334
"Power 37.3W"         = 11 chars × 5,5 =  61px  ->  cabe se começar em ≤ 273
```

Por isso o `Power` está no `goto 250`, não no 290.

## 5. Barras e gráficos

```
${cpubar cpu0 7,334}                       barra: altura,largura
${fs_bar 6,150 /}                          barra de sistema de arquivos
${cpugraph 28,434 1b0033 a45cff}           gráfico: altura,largura cor_baixa cor_alta
${downspeedgraph enp7s0 27,434 2e00d1 d1002e}
```

Os gráficos do conky **auto-escalam** pela janela de histórico: cada coluna é colorida
interpolando entre as duas cores conforme o valor. É por isso que um gráfico de rede fica
azul no repouso e vermelho nos picos com `2e00d1 d1002e`.

Detalhe importante: **a cor do gráfico é a cor ativa (`${colorN}`) no momento em que ele é
desenhado**, para a borda. Coloque `${color4}` imediatamente antes do gráfico.

Para dado que não vem do conky, existe `${execbar}`, `${execgraph}` e as versões com
intervalo `${execibar}` / `${execigraph}` — que têm uma armadilha séria, veja
[armadilhas #3](03-armadilhas.md#3-execbar-e-execgraph-não-aceitam-comando-com-argumento).

## 6. Separando as seções

Sem separação visual o painel vira uma parede de texto ilegível. Três coisas resolvem:

1. **linha em branco** antes de cada título;
2. **título em negrito** um degrau maior que o corpo;
3. **régua pontilhada**: `${stippled_hr 1 5}` — espessura 1, espaço 5 entre os pontos.

```
${color0}${font Terminus (TTF):bold:pixelsize=12}CPU${font}${color3}  ${stippled_hr 1 5}
```

## 7. Cor com disciplina

A regra que este painel segue: **cor só nos gráficos**. Todo o resto é branco (valores),
cinza (rótulos) e branco em negrito (títulos). Isso faz o olho ir direto para onde está a
informação que muda.

```lua
color0 = 'ffffff',   -- títulos
color1 = '8b8b93',   -- rótulos
color2 = 'e9e9ef',   -- valores
color3 = '655c73',   -- separadores
color4 = 'a45cff',   -- SÓ gráficos
color5 = 'ff5a4a',   -- alerta
```

Uma variação igualmente boa é o contrário: painel inteiro monocromático e **cor reservada
a alerta** (temperatura alta, disco cheio). O que não funciona é colorir tudo — aí nada
se destaca.

## 8. Fazer caber na tela

Esse é o passo que todo mundo pula e depois descobre com o rodapé cortado. O conky calcula
a altura da janela pelo conteúdo; se passar da tela, ele encosta no topo e o final some.

Para medir a janela de verdade:

```bash
DISPLAY=:0 xdotool search --class Conky | while read id; do
  xdotool getwindowgeometry $id
done
```

Este painel fica em ~1020px numa tela de 1080. **Não sobra espaço**: adicionar uma seção
exige tirar outra, ou reduzir alturas de gráfico. Os pontos de ajuste, do mais indolor ao
mais drástico:

1. altura dos gráficos (`28,434` → `24,434`);
2. `voffset` entre seções;
3. número de linhas nas tabelas de processos;
4. `pixelsize` da fonte — mas 11 já é pequeno, 10 fica difícil de ler.

## Adaptando para outro hardware

| O que trocar | Onde |
|---|---|
| interface de rede | `enp7s0` em toda a seção NETWORK e em `${addr}` / `${downspeedgraph}` |
| sensor de temperatura da CPU | `${hwmon k10temp temp 1}` → `coretemp` em Intel |
| Super I/O (fans, placa) | `${hwmon nct6799 ...}` → veja `sensors` para o nome do seu |
| número de threads | as duas linhas de `${cpubar cpuN}`, de `cpu1` a `cpu16` |
| montagens | os blocos de `${fs_bar}` e o array `MOUNTS` em `scripts/sys.sh` |
| GPU | a seção inteira sai se você não tiver NVIDIA |
