# LDAPoolex

LDAP pool library

LDAPoolex uses the poolboy library for pooling and implements the `Connection` behaviour
for LDAP (re)connection management.

## Installation

Add the following line to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ldapoolex, github: "tanguilp/ldapoolex", tag: "0.1.0"}
  ]
end
```

## Options

- `:name`: the name of the pool (from poolboy). Defaults to `{:local, pool_name}` where
`pool_name` is either the configuration file pool key or the pool name passed as a parameter
to `LDAPoolex.start_link/2`
- `:size`: the initial size of the pool (from poolboy). Defaults to `5`
- `:max_overflow`: the number of *additional* LDAP connections that can be created under
heavy load. Defaults to `5`, which means that by default the maximum number of connections
is `10`
- `:ldap_args`:
  - `:hosts`: the host list under. Note that this latter option must be a **list** of
  **charlists** (see examples below). No defaults
  - `:bind_dn`: the DN to use to authenticate. If not set, the anonymous mode will be used
  instead
  - `:bind_password`: the password associated to the `:bind_dn`
  - `:connection_retry_delay`: connection retry delay when the LDAP connection is lost in
  milliseconds. Defaults to `3000`
  - `:ldap_open_opts`: will be passed as the second parameter of the `:eldap.open/2` function.
  Defaults to `[]`


## Starting a pool

### Configuration file

On startup, the `LDAPoolex` will automatically start the pools configure in the configuration
files under the `:pools` key:

```elixir
use Mix.Config

config :ldapoolex, pools: [
  poule_un: [
    ldap_args: [hosts: ['localhost']],
    size: 5,
    max_overflow: 10
  ],

  poule_do: [
    ldap_args: [hosts: ['ldap-12.sfexm3.domain.local']],
    size: 3,
    max_overflow: 5
  ]
]
```

### Starting a supervised pool

Call the `LDAPoolex.start_link/2` function.

## Usage

The functions of the `LDAPoolex` modules are basically the same as those in the `:eldap` library.
Therefore, beware of the use of charlists (and not strings) as parameters:

```elixir
iex> LDAPoolex.search(:poule_do, [base: 'dc=example,dc=org', filter: :eldap.equalityMatch('uid', 'john')])
{:eldap_search_result,
 [
   {:eldap_entry, 'uid=john,ou=People,dc=example,dc=org',
    [
      {'objectClass', ['inetOrgPerson', 'posixAccount', 'shadowAccount']},
      {'uid', ['john']},
      {'sn', ['Doe']},
      {'givenName', ['John']},
      {'cn', ['John Doe']},
      {'displayName', ['John Doe']},
      {'uidNumber', ['10000']},
      {'gidNumber', ['5000']},
      {'gecos', ['John Doe']},
      {'loginShell', ['/bin/bash']},
      {'homeDirectory', ['/home/john']}
    ]}
 ], []}
```

## `LDAPoolex.ConnectionWorker` module

This module implements the `Connection` and `:poolboy_worker` behaviours and can be used to
create a single LDAP connection (without a pool). In this case, use the
`LDAPoolex.ConnectionWorker.start_link/1` function.
