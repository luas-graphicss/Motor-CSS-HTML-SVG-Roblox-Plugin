# Motor de CSS, HTML e SVG para Roblox

[Read in English](README.md)

Esse plugin permite montar interfaces no Roblox escrevendo HTML, CSS e SVG, do mesmo jeito que se faz numa página web. Você escreve o código num editor dentro do Studio e o plugin transforma tudo em objetos de GUI de verdade do Roblox.

Para isso funcionar eu praticamente tive que escrever um pequeno motor de navegador em Luau. Tem um tokenizador e um parser de HTML que montam a árvore do documento, e um motor de CSS com cascata, variáveis, cores e espaços de cor, gradientes, contadores, container e media queries, âncoras e propriedades lógicas. O layout suporta fluxo normal, flexbox, grid com subgrid, tabelas, múltiplas colunas e elementos posicionados, com o texto em linha quebrando do mesmo jeito que na web. As fontes são lidas direto dos arquivos binários, incluindo WOFF2 com a compressão Brotli, e têm shaping, variações e recursos OpenType. A parte de SVG cobre paths, gradientes e padrões, filtros, marcadores, texto e animações SMIL. Também tem animações e transições de CSS, motion path, controles de formulário, pseudo elementos, entrada de ponteiro e hit testing.

A renderização só redesenha as partes da tela que mudaram, usando regiões sujas, tiles e um orçamento de renderização para o Studio não travar. Um harness de conformidade compara o resultado com referências tiradas do Chromium.

## Como usar

A pasta CssPlugin segue o formato do Rojo, em que a pasta Main vira um Script com as pastas Modules e Templates dentro. Leve a pasta para um place com o Rojo ou outra ferramenta de sincronização, clique com o botão direito em Main no Explorer e escolha Save as Local Plugin. O editor do plugin abre pela aba Plugins. A pasta Templates tem os scripts de cliente que o plugin usa como base, incluindo um script de inicialização e uma página de demonstração que mostra do que ele é capaz.

## Tempo de desenvolvimento

O plugin levou cerca de dois meses e meio para ser feito e está finalizado.

## Licença

GNU General Public License versão 3. O texto completo está no arquivo LICENSE.
