# FiveM QBCore — Base

Servidor base QBCore para estudos/dev.

## Pré-requisitos
- Windows 10/11
- Git
- MariaDB/MySQL (DB `qbcore`, usuário com permissão)
- CFX `FXServer.exe` (txAdmin)

## Como usar
1. Copie `server.cfg.example` para `server.cfg`.
2. Edite:
   - `sv_licenseKey` (Keymaster)
   - `set mysql_connection_string` (usuário/senha do DB)
   - permissões (`add_principal`)
3. Inicie `FXServer.exe` → siga o wizard do txAdmin → **Start Server**.
4. No FiveM: `F8` → `connect 127.0.0.1`.

## Notas
- Para testes externos: libere as portas 30120 TCP/UDP e faça port-forward no roteador.
- Para ambiente fechado/privado: ative whitelist no txAdmin e/ou `sv_master1 ""`.

## Estrutura
