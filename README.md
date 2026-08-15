VNumero App — Fase 1 (Estrutura Base + Supabase)
Módulos novos (account, numbers) organizados para encaixar dentro do
layout de pastas do fork manaoscloud/mnscloud-phoneweb
(lib/src/{account,contacts,voip,call,call_history,settings,audio,diagnostics,shared}).
Importante: este pacote não recria voip/, call/, call_history/,
contacts/, settings/, audio/ nem diagnostics/ — esses continuam
vindo do clone real do fork. Aqui só entram os módulos novos (account
com login real + escolha de número, e numbers com o pool/expiração) e
os ajustes em shared/ (bottom nav) e core/ (Supabase, Isar, rotas).
O que está pronto nesta fase
Login real por e-mail/senha (Supabase Auth — signUp /
signInWithPassword), sem sessão anônima. Ver
lib/src/account/presentation/login_screen.dart.
Trigger no Postgres que cria a linha em profiles automaticamente no
cadastro (handle_new_user).
Schema SQL completo (supabase/schema.sql):
profiles, virtual_numbers, messages (tabela já criada p/ Fase 2)
Funções: generate_number_pool, list_available_numbers,
claim_virtual_number (atômica, evita 2 usuários pegarem o mesmo
número), touch_my_number, expire_inactive_numbers (regra dos 7
dias)
RLS habilitado em todas as tabelas
Onboarding pós-login: escolha de DDD → 3-4 números sugeridos → ativação
Cache local do número ativo em Isar (LocalVirtualNumber)
AppShell com as 5 abas (Discador, Mensagens, Conta, Histórico,
Contatos)
Redirecionamento reativo: go_router escuta onAuthStateChange do
Supabase e manda o usuário para /login, /onboarding ou /app
automaticamente
Todos os números tratados como String, nunca numérico (ver
NumberFormatter)
O que fica para as próximas fases
Fase 2 — Chat/SMS interno: tela de conversas real, Supabase
Realtime na tabela messages, cache em Isar (LocalMessage).
Fase 3 — VoIP App-to-App (WebRTC puro): sinalização via Supabase
Realtime Broadcast (canal por número virtual), flutter_webrtc
direto, sem SIP. Histórico de chamadas (LocalCallLogEntry).
Job agendado (pg_cron ou Edge Function) chamando
expire_inactive_numbers() diariamente.
Integração real com o código de voip/, call/, call_history/,
contacts/, settings/, audio/, diagnostics/ do fork (não
reescrito aqui — ver nota no topo).
Como rodar
Clone o fork manaoscloud/mnscloud-phoneweb e copie estes arquivos
por cima, respeitando os caminhos abaixo (todos relativos à raiz do
projeto).
Crie um projeto em https://supabase.com e rode supabase/schema.sql
no SQL Editor.
Em Authentication > Providers, deixe Email habilitado (padrão)
e desabilite confirmação de e-mail obrigatória se quiser testar rápido
(Authentication > Settings > "Confirm email" = off em dev).
Popule o estoque de números (exemplo, DDD 35, 50 números):
Sql
Instale as dependências:
Bash
Gere os arquivos do Isar (obrigatório antes do primeiro build):
Bash
Rode o app apontando para o seu projeto Supabase:
Bash
Caminhos de todos os arquivos entregues
Código
Próximo passo sugerido
Me diga se quer seguir para a Fase 2 (Chat/SMS) ou Fase 3 (VoIP
WebRTC puro) — e, se puder, cole aqui o conteúdo real de
lib/main.dart e lib/src/account/ do fork clonado, para eu editar em
cima do código de verdade em vez de aproximar pela documentação.
