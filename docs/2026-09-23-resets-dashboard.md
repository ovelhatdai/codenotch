# Resets do Claude e dashboard adaptável — 2026-09-23

O monitor ignorava as ofertas de redefinição do Claude e o dashboard exigia rolagem mesmo em monitores verticais. Esta mudança consulta a oferta por perfil, distingue API restrita de zero créditos e acrescenta um painel que se adapta à janela, com seleção de monitor e arraste entre telas.

PR complementar ao #1. Base: origin/fix/claude-symlink-credentials (806be4e).

## Escopo
- Consultar redefinições extras por credencial Claude, sem resgatar créditos.
- Distinguir ausência de informação, restrição da API, zero e créditos com validade.
- Dashboard com ajuste ao espaço, paginação legível, tela cheia e monitor identificado.
- Arrastar a barra entre monitores e escolher o destino pelo menu.
- Manter isolamento de contas e evitar processos, animações ou consultas contínuas adicionais.

## Evidência e limites
A documentação oficial descreve a oferta em https://support.claude.com/en/articles/17007452-what-is-a-limit-reset.
O cliente Claude Code 2.1.278 consulta GET /api/oauth/usage?cedar_ember=1&skip_spend=1.
A mesma consulta sem skip_spend preserva as métricas de gasto e entrega cedar_ember.
Uma consulta real retornou eligible=false, ineligible_reason=surface: isso NÃO prova zero créditos.
Não implementar POST reset_rate_limits nem automatizar resgate. Endpoint de leitura não publicado: degradar honestamente caso mude.

## Validação planejada
Testes de contratos incompletos, créditos expirados/futuros, limites separados; isolamento de perfis.
Testes geométricos de janela vertical/horizontal/pequena e monitores com coordenadas negativas.
Compilação e testes em série, no máximo dois jobs. Validação física e consumo prolongado devem ser relatados separadamente.

## Implementação
- `cedar_ember=1` na mesma leitura OAuth já feita por perfil, sem segundo pedido nem subprocesso.
- Oferta indisponível/recusada/malformada continua desconhecida, nunca vira zero. Créditos expirados, futuros e pausados não contam como disponíveis.
- Dashboard considera a orientação: duas colunas na vertical, inclusive em monitores largos, com anéis/textos maiores conforme o espaço; até quatro colunas na horizontal.
- Dashboard inicia em ajuste à janela: 1, 2 ou 4 colunas, páginas em janelas menores, detalhes no anel, controles de organização em popover, botão de tela cheia. Histórico e exibição detalhada mantêm rolagem quando necessária.
- Escolha explícita de monitor no menu da barra seleciona uma tela; arraste no modo todas as telas preserva uma barra por tela. Alça acompanha o monitor de destino. Arraste simples move a janela existente livremente, inclusive para o centro de outro monitor. A posição é salva por monitor, preservada nas atualizações e limitada pela área visível. Menu de botão direito oferece “Fixar na borda”; o modo todas as telas mantém uma barra por tela. Não há consulta de rede, timer ou reconstrução de views em cada movimento.
- Cartões com superfície sólida e transição curta de borda no hover, sem pilha de desfoques ou escala/sombra animada. Nenhum loop de animação ou timer novo.

## Robustez do gesto
O arraste passa a usar deslocamento entre posições globais do ponteiro. Eventos com delta zero antes eram interpretados como clique, mesmo atravessando coordenadas de monitores. Teste reproduziu a falha e passou depois da correção; movimento abaixo do limiar continua sendo clique. Durante o arraste, a janela mantém a recepção de eventos mesmo se o ponteiro ultrapassar a área da barra.

## Validação realizada
- Build Debug macOS arm64 e 54 testes direcionados aprovados, em série, com dois jobs e prioridade reduzida.
- Inclui contrato HTTP GET, mesma credencial/resposta, restrição de superfície, validade, dados ausentes, separação entre contas, geometrias vertical/horizontal/pequena, monitores negativos, seleção de tela e preservação do modo todas as telas.
- Prévia nativa do dashboard com oito contas fictícias, sem autenticação ou rede.
- Mais 19 testes aprovados após ajuste de orientação, incluindo prévia nativa 1440×2400 com oito contas fictícias, troca vertical/horizontal sem perder contas e regressões de arraste.
- Mais 17 testes aprovados após a correção do gesto (incluindo os dois testes de eventos do mouse e as regressões da frota de monitores).
- Mais 20 testes aprovados após o arraste livre: persistência por monitor, retorno à borda, posição durante atualizações e mudanças de espaço dos detalhes, coordenadas negativas e preservação de barras em todas as telas.
- Build Release arm64 assinado, instalado e aberto em `/Applications/CodeNotch Pessoal.app`; executável instalado tem o mesmo SHA-256 do build.
- Oito indicadores presentes. Hashes de contas vinculadas e nomes iguais antes/depois; nenhum reset resgatado.
- Menu nativo confirmou “Fixar na borda” e quatro monitores. Automação por coordenadas não confirmou o gesto físico; validação com o usuário permanece pendente.
- Na versão instalada, seleção do dashboard no monitor horizontal e retorno ao vertical confirmados por interface e preferência persistida. Após instalar o ajuste de orientação, “Usar tela vertical” exibiu as oito contas reais em duas colunas, sem rolagem nem paginação nessa janela. Janela menor mostrou seis cartões e paginação, preservando as oito contas.
- Amostra curta após abertura: aproximadamente 106 MB de RSS; não prova consumo prolongado nem resolução dos travamentos.

## Pendências reais
- A API retornou `surface` na consulta autenticada verificada: o PR não promete revelar contagens que o serviço não forneceu. O link oficial depende da conta conectada no navegador; conferir a identidade.
- Caminho legado de leitura por cache/CLI permanece sem metadados de resets; as sessões OAuth independentes usam a nova consulta.
- Validar manualmente arraste físico da barra entre os quatro monitores, tela cheia, desconexão de monitor e consumo prolongado no Mac. A troca do dashboard pelo seletor e pelo atalho vertical foi verificada; isso não comprova o gesto físico da barra nem a resolução dos travamentos relatados.
- PR complementar depende do PR #1 ainda aberto. Não houve merge ou publicação de instalador.
