# External Research Output — Perplexity

> **Status: NON-NORMATIVE RESEARCH.** Raw external research input. Claims must be independently verified against primary sources before affecting specifications.

A pesquisa aponta para uma direção bem clara: o Uruquim deve tratar roteamento, parsing HTTP e observabilidade como problemas de conformance e previsibilidade, não como um catálogo de conveniências. As referências mais fortes sustentam um core pequeno, com dispatch imutável, parsing defensivo e métricas de baixa cardinalidade, enquanto arenas, backpressure e graceful shutdown entram como capacidades de produção bem delimitadas.

1. Roteamento imutável e zero-allocation
Classificação: PHASE3.

Problema concreto: o core precisa resolver rotas com poucos branches, sem alocação no caminho comum, preservando precedência determinística, 404/405 corretos e o padrão da rota para instrumentação.

Evidência da indústria: matchit se apresenta explicitamente como um router de URL de alta performance e zero-copy, e sua documentação descreve uso de radix trie com compartilhamento de prefixos para reduzir a busca a poucos branches.

Ideia transferível para o Uruquim: separar configuração mutável de uma estrutura de dispatch imutável, e usar representação orientada a dados com índices/arrays onde isso reduzir pointer chasing e facilitar a validação de conflitos antes do startup.

O que não deve ser copiado: não copiar a árvore/polimorfismo por inércia, nem assumir que o formato canônico precisa ser uma radix tradicional com ponteiros.

Protótipo ou benchmark descartável: comparar quatro layouts no mesmo conjunto de rotas: nós ligados por ponteiros, arrays com índices, SoA híbrido e uma radix compactada, medindo lookups, build time e footprint.

Métricas e critérios de aceitação: lookup sem alocações, conflito detectado no startup, 405 com Allow sem segundo lookup caro, e manutenção do template original para logs e métricas.

Impacto possível na API pública: baixo, desde que o shape procedural da API não mude.

Risco de virar um Gin: médio se o roteador virar uma camada de helpers múltiplos para o mesmo caso; baixo se houver uma única forma canônica.

Reversibilidade: alta, porque o dispatch interno pode ser substituído sem mudar a superfície pública.

Fontes primárias: matchit docs e repositório, RFC 9110.

2. Extractors tipados sem reflection
Classificação: STUDYNOW.

Problema concreto: o framework quer tipagem forte, sem reflection pesada e sem geração de código, mas ainda precisa distinguir extração por valor, binding de body e cópia persistente explícita.

Evidência da indústria: axum organiza extração como um subsistema separado de extract, enquanto o próprio prompt já aponta que o modelo de extractors deve continuar procedural e previsível para humanos e LLMs.

Ideia transferível para o Uruquim: manter uma família pequena de extractors canônicos com semântica distinta, deixando claro o que é view-only, o que consome body e o que copia para longe do request lifetime.

O que não deve ser copiado: não copiar um sistema aberto de binders ou um Context com armazenamento arbitrário.

Protótipo ou benchmark descartável: testar um conjunto mínimo de extractors explícitos em Odin, com foco em ergonomia de uso e na impossibilidade de ignorar falhas.

Métricas e critérios de aceitação: zero ambiguidades sobre consumo do body, falha sempre explicitada, e exemplos compiláveis que apontem para uma única forma canônica.

Impacto possível na API pública: médio, porque esta é uma área de DX que pode cristalizar cedo.

Risco de virar um Gin: alto se surgirem variantes demais para o mesmo tipo de binding.

Reversibilidade: média, já que uma vez que a ergonomia se espalha, recuar custa mais.

Fontes primárias: prompt do projeto e documentação de axum::extract.

3. Parsing HTTP defensivo e conformance
Classificação: PHASE3.

Problema concreto: o core precisa rejeitar framing ambíguo, mensagens incompletas e combinações inválidas de Content-Length e Transfer-Encoding, com comportamento idêntico entre adapters.

Evidência da indústria: RFC 9112 define a sintaxe de mensagens HTTP/1.1, parsing, connection management e aspectos de segurança; RFC 9110 define semântica e deixa claro quando há ou não conteúdo em respostas.

Ideia transferível para o Uruquim: construir uma conformance suite que viva acima do transporte, para garantir que qualquer backend interno preserve exatamente os mesmos erros, limites e rejeições.

O que não deve ser copiado: não empurrar regras de parsing para a aplicação nem misturar semântica de request com detalhes do transporte público.

Protótipo ou benchmark descartável: corpus de casos com framing conflitante, chunking inválido, bodies truncados, HEAD/204/304 sem conteúdo e requests com métodos e headers malformados.

Métricas e critérios de aceitação: mesma decisão em todos os adapters, sem divergência de status/erro, e sem exposição de detalhe interno ao cliente.

Impacto possível na API pública: baixo, porque isso deve permanecer abaixo do boundary do transporte.

Risco de virar um Gin: baixo, desde que a API pública não comece a refletir exceções transport-specific.

Reversibilidade: alta, porque o teste de conformance pode crescer sem alterar o core externo.

Fontes primárias: RFC 9110 e RFC 9112.

4. Arenas por requisição e buffers reutilizáveis
Classificação: PHASE3.

Problema concreto: o sistema precisa evitar retenção acidental de views da requisição, controlar o crescimento após requests grandes e separar lifetime de request, connection e aplicação.

Evidência da indústria: o modelo de graceful shutdown da Pingora mostra que o serviço precisa controlar a vida útil das requisições sem interromper o tráfego de forma brusca, e o prompt já exige estudo de arena por requisição e retenção.

Ideia transferível para o Uruquim: usar arena por request e buffers reutilizáveis, mas com regras explícitas para limpezas que não podem depender só da destruição da arena.

O que não deve ser copiado: não assumir que toda alocação pode viver no request arena, nem esconder retenção em helpers mágicos.

Protótipo ou benchmark descartável: comparar comportamento de um request pequeno, um request muito grande e uma sequência mista, medindo pico de memória, retenção e custo de reset.

Métricas e critérios de aceitação: após request grande, memória reutilizável deve voltar a um patamar saudável; nenhuma view deve escapar sem cópia explícita.

Impacto possível na API pública: médio, porque pode exigir APIs explícitas de cópia/persistência.

Risco de virar um Gin: médio se o modelo de lifetime for escondido atrás de conveniências.

Reversibilidade: média, pois decisões de ownership tendem a se espalhar.

Fontes primárias: prompt do projeto e documentação de graceful shutdown da Pingora.

5. Backpressure, timeouts e observabilidade
Classificação: PHASE4.

Problema concreto: o framework precisa lidar com clientes lentos, overload, shutdown gracioso e métricas úteis sem explodir cardinalidade.

Evidência da indústria: o OpenTelemetry estabilizou convenções HTTP e destacou que atributos e métricas devem evitar cardinalidade explosiva, enquanto a Pingora documenta garantias de graceful restart/shutdown com requests atendidas pelo servidor antigo ou novo.

Ideia transferível para o Uruquim: instrumentar por padrão de rota e não por URI crua, e tratar backpressure como contrato de produção, não como detalhe do transporte.

O que não deve ser copiado: não amarrar a semântica de concorrência a um event loop específico, nem fazer hooks de observabilidade bloquearem o hot path.

Protótipo ou benchmark descartável: simular clientes lentos, filas, timeouts e shutdown com requests em andamento, medindo taxa de rejeição, latência e perda de requests.

Métricas e critérios de aceitação: métricas com baixa cardinalidade, shutdown sem corte abrupto de requests elegíveis, e comportamento idêntico entre adapters.

Impacto possível na API pública: baixo a médio, dependendo de como limites e timeouts forem configurados.

Risco de virar um Gin: alto se observabilidade virar pacote de helpers espalhados e não um núcleo de política bem definido.

Reversibilidade: média, porque telemetria tende a criar dependências operacionais.

Fontes primárias: OpenTelemetry HTTP semantic conventions e Pingora graceful docs.

Pontos cegos encontrados
Um ponto cego importante é a estratégia exata de layout dos nós do roteador em Odin: há boa evidência para tries compactadas e zero-copy, mas a decisão entre ponteiros, índices e arrays precisa de protótipo local.

Outro ponto cego é a separação entre limpeza de request e limpeza de conexão; o prompt menciona isso, mas a indústria costuma resolver com políticas de lifecycle que variam bastante por backend.

Também falta validar o limite prático entre view-only e persistent-copy para extractors, porque a ergonomia pode degradar rápido se houver muitas formas.

Ideias rejeitadas
Rejeitar “muitas formas de bind” é correto, porque o prompt já considera isso uma fonte de confusão e de deriva para kitchen sink.

Rejeitar exposição de transporte na API pública é obrigatório, porque congelaria prematuramente detalhes internos.

Rejeitar OpenAPI, WebSocket, streaming e HTTP2 como prioridade agora também está alinhado ao prompt.

Rejeitar middleware genérico estilo Context com mapa arbitrário evita a segunda API canônica para o mesmo problema.

Ordem de pesquisa
Roteador imutável e representações data-oriented.

Conformance HTTP e corpus de parsing defensivo.

Arenas por requisição, retenção e limpeza por lifecycle.

Extractors canônicos e ergonomia sem reflection.

Backpressure, shutdown e observabilidade de baixa cardinalidade.

Experimentos descartáveis
Comparar 3 a 4 layouts de router com o mesmo corpus de rotas.

Implementar um corpus mínimo de conformance HTTP com casos de framing ambíguo.

Medir retenção de memória com request grande seguido de tráfego normal.

Testar uma família mínima de extractors explícitos com erros previsíveis e uma única semântica para body consumption.

Validar métricas por padrão de rota, não por path bruto.

Decisões humanas
Escolher se o custo de uma arena por request compensa a complexidade operacional em cenários reais.

Definir o nível exato de agressividade para rejeitar mensagens malformadas versus tolerar inputs ambíguos.

Determinar se o roteador deve otimizar mais para build-time validation ou para runtime compactness.

Fixar o conjunto mínimo de extractors canônicos que ainda cobre JSON APIs reais sem criar variantes demais.

Conclusão
As ideias que merecem ADR agora são: roteador imutável data-oriented, parsing HTTP defensivo com conformance suite, e observabilidade por padrão de rota com baixa cardinalidade.

As ideias que devem permanecer como pesquisa, por enquanto, são: layout exato do router em Odin, modelo final de arenas por requisição, e desenho fino dos extractors tipados.
