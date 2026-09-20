# Controle TV para macOS

MVP nativo em SwiftUI para descoberta e controle de TVs na rede local.

## Executar

Ao clonar o repositório, inicialize o núcleo Android TV incluído como
submódulo:

```sh
git submodule update --init --recursive
```

Abra `Package.swift` no Xcode 26 ou execute:

```sh
swift run
```

O macOS pedirá acesso à rede local na primeira execução. A descoberta inicial consulta serviços Bonjour comuns (`_googlecast._tcp`, `_androidtvremote2._tcp`, `_androidtvremote._tcp`, `_airplay._tcp` e `_roku._tcp`).

## Protocolo Android TV

Para a AIWA Android TV, o fluxo escolhido é o Android TV Remote v2: descoberta
por `_androidtvremote2._tcp`, pareamento TLS/protobuf na porta `6467` com PIN
de seis caracteres exibido na TV e canal de comandos persistente na porta
`6466`. A identidade RSA do Mac deverá permanecer no Keychain para que o
pareamento não seja repetido.

## Estado atual

O cliente Android TV Remote v2 está integrado. Na primeira tentativa de
pareamento, o app gera uma identidade RSA local, guarda os dados no Keychain,
solicita o PIN mostrado na TV e abre o canal de comandos. Em usos seguintes,
ele reutiliza a identidade para reconectar sem pedir o PIN novamente.

O arquivo `RemoteAdapter.swift` mantém a interface independente da marca; o
transporte Android TV está em `AndroidTVRemoteClient.swift`.
