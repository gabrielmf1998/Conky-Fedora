# O ícone de bandeja

O painel é um processo do conky; o tray é só um controle remoto dele. Vale entender a
divisão antes de mexer.

---

## Quem manda em quem

```
conky-panel-tray.service      ícone na bandeja (PySide6)
        │
        │  systemctl --user start/stop/enable
        ▼
conky-fedora-panel.service    conky -c ~/.config/conky/pride/pride.conf
```

O tray **não roda o conky como filho dele**. Ele fala com o systemd. Isso tem três
consequências boas:

1. fechar o tray não derruba o painel;
2. o painel reinicia sozinho se cair (`Restart=on-failure`);
3. "iniciar no login" é `systemctl --user enable`, não um arquivo de autostart solto — o
   systemd resolve a ordem com o `graphical-session.target`.

São **dois interruptores separados** no menu justamente por isso: dá para ter o painel
subindo no login sem o tray, ou o tray sem o painel.

## A config é do usuário, não do pacote

O pacote instala a cópia intocada em `/usr/share/conky-fedora-panel/`. Na primeira
execução, o tray copia para `~/.config/conky/pride/` **se ainda não existir**.

Atualizar o pacote nunca sobrescreve o que você editou. Para voltar à versão de fábrica há
o *Reset config*, que guarda a sua como `pride.conf.bak` antes.

Os scripts em `scripts/` são copiados junto e com permissão de execução — a config aponta
para `~/.config/conky/pride/scripts/`, então tudo continua num lugar só, editável.

## Detectando um conky "solto"

Se você já rodava o painel por um `.desktop` de autostart, existe um conky com a sua
config que o systemd não conhece. O tray varre `/proc` procurando por um processo cujo
cmdline contenha o caminho da config, e mostra **"running (outside the service)"**.

Ao ligar pelo menu, ele mata o processo solto antes de subir a unidade, para não ficarem
dois painéis desenhados um por cima do outro. Ligar "iniciar no login" também apaga o
`.desktop` legado, pelo mesmo motivo.

## Desenhar ícone que se lê em 22px

A bandeja é minúscula. O que funcionou:

- **vetor desenhado em runtime**, num espaço 100x100 escalado para o tamanho pedido, e
  registrado no `QIcon` em vários tamanhos (`22, 32, 48, 64, 128`). A bandeja escolhe;
  nada de PNG desalinhado;
- **traço grosso**. Linhas de 7 a 9 unidades num espaço de 100. Detalhe fino vira mancha
  cinza em 22px;
- **o estado tem que se ler pela forma, não só pela cor**. Ligado/desligado aqui muda o
  desenho: nos estilos de onda a linha **fica reta** quando o painel está parado, o ponto
  fica oco, as barras achatam. Cor sozinha não sobrevive a um tema claro nem a daltonismo;
- **sem texto**. Número em 22px só funciona com 2 dígitos e fonte bold — e mesmo assim é o
  último recurso.

## Consumo

O tray consulta o estado a cada 4 segundos (`systemctl is-active`, `is-enabled` e uma
varredura curta de `/proc`). Fora isso ele fica parado — não há timer de animação.

## A regra do RAPL

O campo `Power` da CPU lê `/sys/class/powercap/intel-rapl:0/energy_uj`, que é **root-only
por padrão** desde o PLATYPUS (CVE-2020-8694): leitura de energia em alta resolução serve
de canal lateral.

O pacote **não** instala essa regra sozinho — mexer em permissão de sensor sem o usuário
saber seria feio. O item *Enable CPU power readings* no menu explica o que faz e instala
via `pkexec`, liberando para o grupo `wheel`, não para o mundo. Enquanto não for
instalada, o campo fica vazio e o resto do painel funciona igual.

O item some do menu quando a leitura já está liberada.
