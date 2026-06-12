# Learning Journal

Este journal documenta a história do repositório até o commit `6f69cc0`, que é o
`HEAD` gravado no momento desta edição.

## Como este journal usa evidências

- Base primária:
  `git log`, `README.md`, `docs/decisions.md`, controllers, services de
  discovery/ingestion/matching e a suíte de testes.

- Quando o texto fala de produto “Farol”, “fallback Codex” ou “matching por
  perfil”:
  a leitura se apoia em commits, docs e superfícies reais do código.

- Escopo:
  commits já gravados até `6f69cc0`. Existem mudanças não commitadas nesta árvore
  de trabalho fora deste journal; elas não entram nas afirmações históricas.

## O que o histórico não prova

- O histórico não prova cobertura perfeita de todos os job boards.
- Não prova recall/precision com dataset rotulado externamente.
- Não prova tração real de usuários da marca Farol.

## 1. Objetivo do projeto

Este projeto existe para ensinar como um produto Rails pode ser o dono da
persistência canônica, classificação e operação de descoberta de vagas mesmo
quando parte da busca depende de adapters frágeis ou de fallback assistido por
Codex.

O repositório quer tornar explícitas as camadas do problema:

- descoberta de vagas em fontes heterogêneas;
- ingestão segura e rastreável;
- persistência canônica;
- matching por perfil;
- fallback assistido para fontes bloqueadas;
- apresentação do produto tanto para operador quanto para visitante.

Ao terminar este journal, o leitor deve conseguir:

- seguir uma vaga desde um adapter até `Job`, `SearchRun`, `SourceScan` e
  `JobMatch`;
- explicar por que Rails discovery e Codex fallback coexistem em vez de competir;
- apontar onde vivem as decisões de matching e onde vivem as decisões de produto;
- reconstruir a evolução recente até a camada pública Farol.

## 2. Como ler o repositório primeiro, em ordem de aprendizado

1. Leia `README.md`.
2. Leia `config/routes.rb`.
3. Leia `app/controllers/jobs_controller.rb`,
   `app/controllers/search_runs_controller.rb`,
   `app/controllers/sources_controller.rb` e
   `app/controllers/pages_controller.rb`.
4. Leia `app/services/job_discovery/adapters/base.rb` e depois um adapter real:
   `app/services/job_discovery/adapters/gupy_company_boards_adapter.rb`.
5. Leia `app/services/job_discovery/fetcher.rb` e
   `app/services/job_discovery/orchestrator.rb`.
6. Leia `app/services/job_discovery/` e os models `Job`, `SearchProfile`,
   `JobMatch`, `SearchRun`, `SourceScan` e `DiscoveredJob`.
7. Leia `docs/decisions.md`.
8. Feche com:
   `test/controllers/pages_controller_test.rb`,
   `test/controllers/sources_controller_test.rb`,
   `test/models/job_match_test.rb`,
   `test/services/job_match_filters_test.rb`,
   `test/jobs/discover_jobs_run_job_test.rb`.

### O que ignorar na primeira passada

- Não comece por landing/branding.
  A homepage Farol faz mais sentido depois que o pipeline de discovery está claro.

- Não confunda “vaga descoberta” com “vaga persistida e classificada”.
  Esse é um boundary central do produto.

## 3. História cronológica da implementação

### Fase 1: app privada, ingestão e dashboard básico (`fd7817a` a `f78380a`, 2026-06-06)

- O projeto começou com skeleton Rails 8, tooling, autenticação privada, domínio
  de vagas e runs, ingestão segura, dashboard básico, bootstrap admin e deploy
  Railway com worker.
- Essa fundação já mostra uma escolha certa: o produto nasceu como sistema de
  operação e rastreabilidade, não como scraper ad hoc.
- Base usada:
  commits `fd7817a` a `f78380a`; controllers principais, models base e README.

### Fase 2: expansão agressiva da descoberta nativa (`865460a` a `35776cb`, 2026-06-06 a 2026-06-07)

- Esta é a fase mais longa e define a personalidade técnica do repositório.
- Entram discovery tracking models, backfill determinístico, dezenas de adapters
  nativos, source-scoped runs, source admin, scheduler diário e o primeiro
  desenho explícito de Codex fallback.
- O histórico aqui é o de um specialist transformando scraping em sistema
  operável: coverage por fonte, cold boot de catálogos, preservação de override,
  contratos de adapter suportado e ruído reduzido em resultados.
- Base usada:
  commits `865460a` a `35776cb`; `app/services/job_discovery/adapters/*`,
  `app/controllers/sources_controller.rb`, `app/controllers/search_runs_controller.rb`,
  `README.md`.

### Fase 3: matching por perfil e radar configurável (`55e2f3d` a `a4da3f0`, 2026-06-07 a 2026-06-09)

- O produto deixa de ser só “coletor de vagas” e vira radar por intenção do
  usuário.
- Entram search profiles configuráveis, policy dirigida por profiles, job matches
  por profile, dashboard por perfil, linguagem/título, compile de intenção,
  sync assíncrono e cleanup de filtros legados.
- A lição importante aqui: a unidade principal do produto passa de `Job` para
  `Job + intenção do operador`.
- Base usada:
  commits `55e2f3d` a `a4da3f0`; `SearchProfile`, `JobMatch`,
  tests de profiles e matching.

### Fase 4: hardening de produto e nascimento da marca Farol (`dc32f53` a `6f69cc0`, 2026-06-10 a 2026-06-12)

- `dc32f53` alinha runtime para Ruby 3.4.9, endurece SSL e remove N+1 de
  discovery.
- `a449c9a` endurece o fetcher com retry, backoff, jitter e host throttling.
- `ecff2ee` cria um decision journal explícito.
- `1a15b41`, `7aacb07`, `2da21cc`, `a09c240` e `3101e90` deslocam o produto de
  “dashboard interno com uma landing separada” para “Farol como frente pública
  honesta”.
- `4b38264` e `6f69cc0` mostram que o trabalho técnico continuou depois do
  branding: centralização de upsert de matches e separação entre compilação e
  avaliação de policy.
- Base usada:
  commits `dc32f53`, `ecff2ee`, `a449c9a`, `1a15b41`, `7aacb07`, `2da21cc`,
  `a09c240`, `3101e90`, `4b38264`, `6f69cc0`; `docs/decisions.md`.

## Features importantes como unidades completas

### Descoberta nativa por adapters com operação explícita

- Problema que resolve:
  vagas chegam de ATSs e boards com contratos e fragilidades diferentes.

- Commits principais:
  `62d7a64`, `3574fb1`, `813bfd8`, `7586111`, `151e979`, `6dc1b5d`, `45681e3`,
  `c63df31`, `5614c2d`, `067d81d`, `5fe5d1d`.

- Arquivos principais:
  `app/services/job_discovery/adapters/*`,
  `app/services/job_discovery/orchestrator.rb`,
  `app/controllers/sources_controller.rb`,
  `app/controllers/search_runs_controller.rb`.

- Por que a solução final tomou essa forma:
  o produto preferiu adapter + source catalog + run tracking em vez de scrapers
  soltos sem memória operacional.

- Testes e sinais:
  `test/jobs/discover_jobs_run_job_test.rb`,
  controllers de sources/runs e docs registrando coverage por fonte.

### Matching por perfil e job matches persistidos

- Problema que resolve:
  a mesma vaga não tem o mesmo valor para todo operador.

- Commits principais:
  `2a14095`, `9da14d5`, `a1696e9`, `c54d39a`, `a57d75a`, `08bf29d`, `a4da3f0`,
  `4b38264`, `6f69cc0`.

- Arquivos principais:
  `SearchProfile`,
  `JobMatch`,
  `app/services/job_discovery/*`,
  `test/models/job_match_test.rb`,
  `test/services/job_match_filters_test.rb`.

- Prós:
  o produto sai de “caixa de entradas de vagas” para “radar orientado a intenção”.

- Contras:
  matching vira subsistema próprio e exige mais disciplina de sync e cache.

### Codex fallback como arquitetura declarada, não gambiarra

- Problema que resolve:
  algumas fontes não são estáveis o suficiente para worker Rails puro.

- Commits principais:
  `b2fb9e2`, `35776cb`, `55e2f3d`.

- Arquivos principais:
  `README.md`,
  `app/controllers/search_runs_controller.rb`,
  `app/controllers/sources_controller.rb`.

- O que isso ensina:
  fallback assistido pode ser parte legítima do produto quando é explícito,
  estreito e revalidado pelo backend.

### Farol como camada pública honesta

- Problema que resolve:
  o produto precisava explicar valor sem mentir sobre cobertura, frequência ou
  uma waitlist inexistente.

- Commits principais:
  `1a15b41`, `7aacb07`, `2da21cc`, `a09c240`, `3101e90`.

- Arquivos principais:
  `app/controllers/pages_controller.rb`,
  `app/views/pages/home.html.erb`,
  `test/controllers/pages_controller_test.rb`,
  `docs/decisions.md`.

## 4. Decisão por decisão

- Rails como dono da persistência canônica:
  escolhido para não transformar matching em efeito colateral de automação.

- Adapter nativo quando possível, fallback Codex quando necessário:
  escolhido para manter confiabilidade sem fingir universalidade técnica.

- Profile-driven matching:
  escolhido porque o produto não é só coleta; é seleção contextual.

- Landing Farol com números reais do catálogo:
  escolhida para alinhar a superfície pública com o runtime real do produto.

## 5. Prós e contras das escolhas principais

- Catálogo de sources explícito:
  pró: operação e cobertura observáveis.
  contra: custo de manutenção cresce.

- Matching persistido por profile:
  pró: experiência mais útil.
  contra: mais modelos, syncs e edge cases.

- Fallback assistido:
  pró: honestidade operacional.
  contra: admite que nem toda fonte cabe no worker Rails puro.

## 6. Erros, correções e endurecimentos

- O histórico mostra várias correções de race, host scoping, source uniqueness,
  URL sanitization e sync de profile.
- A fase final também deixa claro que o produto estava pronto o bastante para
  branding só depois de endurecer runtime, fetcher e quality posture.

## 7. Como os testes foram usados

- Primeiro para validar controllers e models do dashboard.
- Depois para proteger discovery jobs, matching e filters.
- Por fim para travar o comportamento público da landing Farol e a coerência da
  proposta do produto.

## 8. Quais testes protegem quais decisões

- Discovery e runs:
  `test/jobs/discover_jobs_run_job_test.rb`,
  `test/controllers/search_runs_controller_test.rb`,
  `test/controllers/sources_controller_test.rb`.

- Matching:
  `test/models/job_match_test.rb`,
  `test/services/job_match_filters_test.rb`,
  `test/services/job_title_language_test.rb`.

- UI privada e profiles:
  `test/controllers/search_profiles_controller_test.rb`,
  `test/system/search_profiles_test.rb`.

- Superfície pública Farol:
  `test/controllers/pages_controller_test.rb`,
  `test/controllers/waitlist_entries_controller_test.rb`.

## 9. Timeline dos commits atômicos

| Commit | Pergunta que o commit responde | Mudança principal | Prova |
| --- | --- | --- | --- |
| `fd7817a` | Como iniciar a base? | skeleton Rails 8 | scaffold |
| `5204396` | Qual é a barra mínima? | tooling e CI | CI |
| `7dcf1f9` | Como restringir a UI? | auth privada | controllers/tests |
| `4d23ba3` | Quais são os agregados principais? | jobs e runs | models |
| `9019745` | Como ingerir com segurança? | ingestion API | request path |
| `a1a2132` | Como operar o radar? | dashboard filters e run browsing | UI |
| `f78380a` | Como rodar em Railway? | deploy + worker | ops |
| `62d7a64` | Como rastrear discovery? | tracking models | models |
| `3574fb1` | Como fazer backfill determinístico? | adapters + trigger | jobs/services |
| `7586111` | Como aumentar coverage nativa? | Lever/Greenhouse/Ashby | adapters |
| `151e979` | Como cobrir Inhire? | adapter Inhire | adapter |
| `6dc1b5d` | Como cobrir Recrutei? | adapter Recrutei | adapter |
| `45681e3` | Como cobrir Sólides? | adapter Sólides | adapter |
| `c63df31` | Como cobrir Teamtailor? | adapter Teamtailor | adapter |
| `5614c2d` | Como cobrir SmartRecruiters? | adapter SmartRecruiters | adapter |
| `067d81d` | Como cobrir Trampos? | adapter Trampos | adapter |
| `5fe5d1d` | Como cobrir Coodesh? | sitemap discovery | adapter |
| `b2fb9e2` | Como lidar com fontes bloqueadas? | codex fallback explícito | README/docs |
| `2a14095` | Como tornar o radar configurável? | search profiles | models/controllers |
| `a1696e9` | Como persistir decisão por perfil? | job matches | models |
| `c54d39a` | Como mostrar radar por perfil? | profile scoped radar | UI |
| `a57d75a` | Como compilar intenção? | intent-compiled profiles | matching core |
| `dc32f53` | O runtime está alinhado? | Ruby 3.4.9 + SSL + N+1 cut | runtime |
| `a449c9a` | Fetcher já é resiliente? | retry/backoff/jitter/throttling | service |
| `ecff2ee` | Como registrar decisões? | decision journal | docs |
| `1a15b41` | Como apresentar o produto? | landing Farol estática | product surface |
| `7aacb07` | Qual é a homepage real? | root público com login | routes/controller |
| `2da21cc` | A landing está honesta? | dados reais e CTAs corretos | tests |
| `a09c240` | A waitlist placeholder ainda existe? | form desabilitado | tests |
| `3101e90` | Como capturar interesse? | waitlist via Resend | feature |
| `4b38264` | Onde vive o upsert de match? | centralização do upsert | matching code |
| `6f69cc0` | Como separar policy de execução? | split compilation vs evaluation | matching architecture |

## 9A. Perguntas de recuperação

- Onde uma vaga deixa de ser descoberta e vira registro canônico?
- Por que `JobMatch` existe em vez de decidir tudo em tempo de render?
- O que o fallback Codex preserva e o que ele delega de volta para Rails?

## 10. Comandos de terminal que um specialist usaria aqui

```bash
git log --oneline --reverse
git show --stat a449c9a
bin/rails test test/jobs/discover_jobs_run_job_test.rb
bin/rails test test/models/job_match_test.rb
bin/rails test test/controllers/pages_controller_test.rb
bin/rails test
bin/rubocop
bin/brakeman -q -w2
bin/rails "dashboard:discover[20]"
```

## 11. Como adicionar a próxima feature sem quebrar a aula

Se a próxima feature for uma nova fonte:

1. crie adapter próprio;
2. decida se ela entra em Rails discovery ou fallback assistido;
3. atualize o catálogo e a operação de source;
4. prove ingestão, dedupe e impacto no matching;
5. só depois reflita isso na superfície pública Farol, se for relevante.

## 12. Limites de produção deixados de propósito

- não prova cobertura universal de job boards;
- não tenta resolver scraping hostil como se fosse estável por definição;
- não prova qualidade de matching com ground truth externo;
- mantém o foco em operação, learnability e honestidade do produto.
