# External Research Output — Gemini

> **Status: NON-NORMATIVE RESEARCH.** Raw external research input. Claims must be independently verified; arbitrary thresholds and public API suggestions are not project decisions.

Como Arquiteto de Software Sênior e pesquisador de sistemas, analisei as restrições arquiteturais e os objetivos do Uruquim. Baseando-me em princípios de programação de sistemas (C, Zig, Rust), Data-Oriented Design e na filosofia da linguagem Odin, apresento a pesquisa direcionada para as Fases 3 e 4.

Reconheço que não possuo acesso ao código-fonte do Uruquim e que o projeto busca equilibrar performance, produtividade e legibilidade para IA sem recorrer a "magia" ou "god objects".

Abaixo está o resultado da pesquisa estruturada conforme solicitado.

---

### Executive Summary

O Uruquim apresenta uma fundação sólida ao priorizar controle explícito e rejeitar abstrações de alto custo (como `map[string]any` ou reflection pesada). A transição para as Fases 3 e 4 exige consolidar o *hot path* utilizando estruturas de dados planas (Data-Oriented Design), isolar o gerenciamento de memória através de ciclos de vida estritos (Connection vs. Request) e blindar o *core* através de um conjunto de testes de conformidade para o limite de transporte. O foco primário deve ser transformar configurações mutáveis de *startup* em estruturas de dados de *runtime* puramente estáticas e eficientes para o cache da CPU.

---

### Recomendação 1: Roteamento Imutável Baseado em Arrays (Flattened Radix)

* **Classificação:** PHASE_3
* **Problema concreto:** Árvores Radix tradicionais baseadas em ponteiros geram *pointer chasing*, causando frequentes *cache misses* (L1/L2) durante a travessia das rotas em cenários de alta concorrência. Adicionalmente, a extração de parâmetros frequentemente resulta em alocações dinâmicas.
* **Evidência da indústria:** Projetos como `matchit` (Rust) provam que roteadores de altíssima performance se beneficiam da redução de ponteiros. A técnica *Structure of Arrays* (SoA) ou arrays contíguos de nós indexados matematicamente são padrões comuns em engines de jogos e parsers de alta performance (C/Zig).
* **Ideia transferível para o Uruquim:** Implementar duas fases de ciclo de vida para o roteador. Durante o *startup* (mutável), uma árvore Radix tradicional ou um construtor de grafo é usado para detectar conflitos e estabelecer precedência. Antes de servir, essa árvore é "compilada" (achatada) em um array contíguo de nós (`[]Node`). A navegação usa índices (`u16` ou `u32`) em vez de ponteiros. Para parâmetros, o roteador pré-calcula a profundidade máxima de parâmetros da árvore e o *handler* recebe uma *slice* de tamanho fixo alocada no *stack* ou pré-alocada por *worker*, armazenando apenas as *views* (fatias da string original do *path*).
* **O que não deve ser copiado:** A complexidade de compressão de caminhos extremos do `httprouter` (Go), que pode dificultar a legibilidade do código e o diagnóstico de falhas para agentes de IA.


* **Protótipo ou benchmark descartável:** Criar um benchmark comparando a travessia de uma árvore ligada por ponteiros versus uma busca iterativa em um `[]Node` achatado com índices, medindo *cache misses* usando `perf`.
* **Métricas e critérios de aceitação:** Zero alocações de memória no *lookup* da rota (caminho feliz e erro 404). Geração determinística de erro 405 (Method Not Allowed) sem precisar percorrer a árvore inteira repetidas vezes.


* **Impacto possível na API pública:** Nenhum. A API procedural `web.get(...)` permanece inalterada; apenas o motor interno muda.


* **Risco de virar um “Gin”:** Baixo. É uma otimização puramente interna e encapsulada.
* **Reversibilidade:** Alta. Como a API pública não muda, o motor de roteamento pode ser revertido se a complexidade de manutenção superar os ganhos de performance.
* **Fontes primárias:** Princípios de DOD (Mike Acton); implementação de *flat arrays* em roteadores de Rust.

### Recomendação 2: Tiered Allocators com Controle de Retenção (Watermarking)

* **Classificação:** PHASE_3
* **Problema concreto:** Requisições grandes ou prolongadas podem inflar permanentemente o consumo de memória do servidor se buffers reutilizáveis ou arenas não tiverem um limite de liberação (*retention policy*).
* **Evidência da indústria:** O NGINX utiliza *memory pools* atrelados à requisição de forma altamente otimizada. O H2O HTTP server demonstra como separar buffers do ciclo de vida da conexão do ciclo de vida da requisição.
* **Ideia transferível para o Uruquim:** Utilizar uma abordagem de *allocator* em três níveis:
1. **Connection-level Ring Buffer:** Para leitura bruta da rede, reutilizado entre requisições na mesma conexão (Keep-Alive).
2. **Per-Request Arena:** Um *scratch allocator* para dados derivados da requisição. Toda extração que precise materializar dados temporários usa esta arena.
3. **High-Watermark Drop:** Se a arena de uma requisição ultrapassar um limite predefinido (ex: 64KB) para processar um *payload* grande, ela é destruída ao final da requisição em vez de ser reciclada, devolvendo a memória ao SO e evitando inchaço residual (*memory bloat*).


* **O que não deve ser copiado:** A vinculação complexa entre o *pool* de memória e as estruturas internas do S.O. (como visto em servidores C muito antigos).
* **Protótipo ou benchmark descartável:** Implementar um servidor *dummy* que recebe 99% de requisições pequenas (1KB) e 1% de requisições massivas (5MB). Observar a estabilidade do *Resident Set Size* (RSS) no Linux com e sem a política de *high-watermark*.


* **Métricas e critérios de aceitação:** O consumo de memória RSS deve retornar à linha de base após um pico de requisições anômalas.
* **Impacto possível na API pública:** Requer deixar claro na documentação (e para a IA) que qualquer dado extraído via `web.path_int` ou *body parsers* não sobrevive ao retorno do *handler* a menos que o usuário o copie para o *allocator* da aplicação.


* **Risco de virar um “Gin”:** Baixo. Mantém o princípio de controle explícito.


* **Reversibilidade:** Média. Mudar a semântica de *lifetime* de variáveis extraídas afeta todo o código do usuário.
* **Fontes primárias:** Documentação de arquitetura do NGINX; código fonte do `std.heap.ArenaAllocator` do Zig.

### Recomendação 3: Protocolo Defensivo via "Conformance Corpus"

* **Classificação:** PHASE_4
* **Problema concreto:** Múltiplos adaptadores de transporte (ex: um customizado via `epoll` e o futuro `core:net/http` do Odin) podem interpretar o *framing* HTTP de forma diferente, abrindo espaço para *HTTP Request Smuggling* (CWE-444).


* **Evidência da indústria:** Parsers como `llhttp` (Node.js) e ferramentas como o HTTP Request Smuggling testing framework do PortSwigger. A RFC 9112 detalha estritamente como tratar falhas de formatação.
* **Ideia transferível para o Uruquim:** Não tentar cobrir todas as falhas no *core*, mas sim criar um **Uruquim Transport Conformance Suite** interno. Um conjunto de testes de contrato rigoroso contendo casos de *chunking* inválido, cabeçalhos duplicados (`Content-Length` conflitante com `Transfer-Encoding`), e URIs malformadas. Qualquer adaptador (seja escrito por terceiros ou o futuro oficial) deve passar por essa *suite* para ser considerado seguro. O adaptador deve rejeitar a requisição *antes* de enviá-la ao Uruquim.
* **O que não deve ser copiado:** Escrever um parser HTTP do zero em Odin dentro do repositório *core* do microframework, se o objetivo do limite conceitual de transporte é justamente isolar o *core* dessa responsabilidade.


* **Protótipo ou benchmark descartável:** Extrair 20 vetores de ataque comuns de *smuggling* da RFC 9112 e criar um script de teste em Odin que instancie um *handler* bruto para verificar se o status 400 (Bad Request) é retornado imediatamente.
* **Métricas e critérios de aceitação:** 100% de conformidade com a RFC 9112 em relação à prioridade do `Transfer-Encoding` e rejeição de requisições ambíguas.
* **Impacto possível na API pública:** Nenhum no *core*. Impacta apenas a API interna (e não documentada para usuários comuns) de quem escreve adaptadores.
* **Risco de virar um “Gin”:** Zero.
* **Reversibilidade:** Alta.
* **Fontes primárias:** RFC 9112 (Seção 6: Message Framing); RFC 9110.

### Recomendação 4: Extractors Explícitos de Estado Único

* **Classificação:** PHASE_3
* **Problema concreto:** Consumir o corpo da requisição (Body) duas vezes em transportes baseados em *streaming* pode causar *deadlocks* ou comportamentos indefinidos, e tratar erros de extração de forma silenciosa vai contra os princípios do Uruquim.


* **Evidência da indústria:** Axum (Rust) utiliza o sistema de tipos (*Ownership* e *Traits*) para garantir que o corpo só seja consumido uma vez. Sem o *Borrow Checker*, precisamos de garantias em *runtime*.
* **Ideia transferível para o Uruquim:** Manter a extração procedural. O `Context` deve manter uma *flag* interna `body_consumed: bool`. Qualquer função da família `web.body(ctx, &input)` checa essa flag. Se for `true`, ela registra um erro de sistema e retorna `false`. Além disso, para evitar gerar "múltiplas formas de bind", qualquer falha do extrator sempre assume a responsabilidade de enviar o erro HTTP (ex: 400 Bad Request) correspondente, garantindo que o *handler* só precise fazer `if !web.body(...) { return }`.


* **O que não deve ser copiado:** A injeção mágica de dependências através da assinatura do *handler* comum em alguns frameworks Go e C#, que obscurecem a origem dos dados e dificultam o entendimento por IAs.


* **Protótipo ou benchmark descartável:** Escrever um teste simulando uma dupla extração do body e validando se a proteção contra "resposta escrita duas vezes" (Double Render) intercepta corretamente o fluxo sem causar *panic*.


* **Métricas e critérios de aceitação:** Zero *panics* em caso de erro de desenvolvedor (duplo read); resposta padronizada de erro HTTP ao cliente.
* **Impacto possível na API pública:** Retornos booleanos de falha bem delimitados, já previstos na Fase 1.


* **Risco de virar um “Gin”:** Baixo, pois previne atalhos mágicos para lidar com validação de *payload*.
* **Reversibilidade:** Baixa (define o padrão de código da comunidade).
* **Fontes primárias:** *Design docs* do Axum sobre `FromRequest`; princípios de API defensiva em C.

### Recomendação 5: Observabilidade Guiada por Padrão de Rota

* **Classificação:** PHASE_4
* **Problema concreto:** Métricas e logs *ingênuos* usam a URI bruta (ex: `/users/1234`), gerando alta cardinalidade no Prometheus/Grafana e derrubando a infraestrutura de monitoramento.
* **Evidência da indústria:** OpenTelemetry HTTP Semantic Conventions mandam explicitamente agrupar métricas usando o atributo `http.route` (ex: `/users/:id`).
* **Ideia transferível para o Uruquim:** Modificar o mecanismo de *dispatch* (da Recomendação 1) para anexar o "molde" imutável da rota correspondida no `Context` (*view* para string estática registrada no startup) *antes* da execução da cadeia de *middlewares*. Assim, qualquer middleware de métricas pode usar `ctx.route_pattern` com O(1) sem alocação e sem precisar re-parsear a URI.
* **O que não deve ser copiado:** Sistemas complexos de *tracing* embutidos no *core*. O *core* apenas provê o `route_pattern`; o usuário conecta o exportador.
* **Protótipo ou benchmark descartável:** Simular geração de métricas simulando 100 mil caminhos únicos. Medir impacto de memória de agregar por rota dinâmica vs estática.
* **Métricas e critérios de aceitação:** Disponibilidade da string do padrão de rota original (ex: `/users/:id`) no `Context` com zero custo adicional de processamento.
* **Impacto possível na API pública:** Adição segura de um campo ou *getter* como `web.route_pattern(ctx)` focado apenas em leitura para instrumentação.
* **Risco de virar um “Gin”:** Baixo. Ajuda na integridade de produção sem poluir a lógica de negócios.
* **Reversibilidade:** Média, ferramentas de *APM* externas passarão a depender disso.
* **Fontes primárias:** OpenTelemetry HTTP Semantic Conventions (`http.route`).

---

### 1. Pontos Cegos Encontrados

* **Protocol Upgrades (WebSockets e SSE):** Embora descartado do MVP, se o transporte sequestrar a conexão TCP subjacente, o *core* precisa de uma porta de saída mecânica (ex: `web.hijack(ctx)`) nas Fases 3 ou 4 que delegue o ponteiro do *socket* para o usuário, caso contrário será impossível implementar pacotes separados depois.


* **TLS Termination:** O framework não define se será suportado internamente ou se assumirá que um *reverse proxy* (NGINX/Caddy) sempre estará na frente. Em APIs reais, se o proxy faz o TLS, o *core* ainda precisa confiar no *header* `X-Forwarded-Proto` para gerar URIs corretas internamente de forma segura.

### 2. Ideias Rejeitadas e Motivo

* **Map[string]any no Context:** Rejeitado categoricamente. Violaria o DOD, forçaria alocação na *heap* para qualquer inferência de tipo e adicionaria um custo de *boxing* para variáveis não conhecidas.


* **Árvore Radix com Ponteiros C/Go tradicionais:** Rejeitado. Causa fragmentação de memória e degrada a performance de L1 Cache. A abordagem plana (SoA) é superior para Odin.
* **Extração baseada em Reflection:** Rejeitada. Destrói a performance, atrapalha a leitura estática do código (prejudicando LLMs e ferramentas) e embute "magia" não-idiomática para Odin.



### 3. Ordem Recomendada de Pesquisa

1. Roteamento Imutável baseado em Arrays (Define a estrutura central de dados do hot path).
2. Memória: Per-request Arenas & Políticas de Retenção (Impacta diretamente todos os extratores e buffers).
3. HTTP Defensivo & Conformance Suite (Garante que os transportes se comportem corretamente antes de chegar ao código do framework).
4. Procedural Extractors (Consolidando APIs agora que memória e roteamento estão definidos).
5. Observabilidade (Padrão de rotas e métricas limitadas).

### 4. Experimentos Descartáveis Sugeridos

* **Experimento A (Radix Flattening):** Uma POC que pegue 50 rotas estáticas e 10 paramétricas, crie a árvore e a converta para uma *slice* estática (`[]RouteNode`). Comparar ciclos de CPU de uma busca contra uma implementação baseada em ponteiros usando o pacote `core:time` e `perf` do Linux.
* **Experimento B (Watermark Arena):** Construir um simulador HTTP que use o *allocator* padrão versus o *ArenaAllocator* de *fallback* configurável e validar o RSS com ferramentas do S.O. (usando LLVM 20.1.8 em Linux x86-64 como validado na Fase 1).



### 5. Questões que Exigiriam Decisão Humana

* **Alocação de Parâmetros de Rota:** Qual deve ser o número máximo *hardcoded* de parâmetros em uma única URL (ex: 8, 16)? Essa decisão permite o uso de arrays na *stack* (`[16]string`) em vez de *slices* alocadas dinamicamente.
* **Resposta em Limites Ultrapassados:** Quando um cliente lento ou um payload muito grande dispara o *timeout* ou limite de memória, o servidor deve fechar a conexão TCP imediatamente (RST) ou tentar enviar graciosamente um `413 Payload Too Large`?
* **Fronteira do Transporte:** O futuro adaptador de `core:net/http` precisará lidar sozinho com *timeouts* de *read/write*, ou o Uruquim fornecerá estruturas para registrar essas interrupções no ciclo de vida?

### 6. Conclusão

* **Merecem ADR (Architecture Decision Record) e Implementação Direta:** O roteamento por árvore *flattened* baseada em índices (Data-Oriented) e a adoção formal das arenas por requisição com limiares (watermark). Estas afetam estruturalmente a arquitetura e garantem os pilares do framework. A exigência de não usar `map` e de retorno explícito dos extratores também deve ser formalizada nas diretrizes públicas.

* **Devem permanecer como pesquisa contínua:** A suite de testes de *conformance* (pois os transportes do ecosistema Odin ainda estão em evolução, inclusive `core:net/http`) e as decisões granulares de *graceful shutdown* e limitadores de *backpressure* transport-neutral, que dependerão do comportamento real em implantações de teste da Fase 4.
