# Beethoven

A Decentralized failover and peer-to-peer node finder for Elixir. Allows Elixir nodes to find each other automatically. Once connected, they can coordinate to delegate roles and tasks between the nodes in the cluster. Written using only the Elixir and Erlang standard library.

## How to use

Within `mix.exs`, add the below to `deps/0`.

```elixir
defp deps do
    [
        ...
        {:beethoven, "~> 0.0"}
        ...
    ]
end
```

Add `:beethoven` to `:extra_applications` for your `application/0` config within `mix.exs`.


```elixir
def application do
[
    mod: {..., []},
    extra_applications: [:logger, :runtime_tools, :beethoven]
]
end
```

Add dependencies via `mix` in a shell session.

```bash
$> mix Deps.get
```

Then within `config.exs`, or your preferred config file, input the below config.

```elixir
# Configuration for the Beethoven stack
config :beethoven,
  use_az_net: false,
  cluster_net: "127.0.0.0",
  cluster_net_mask: "29",
  listener_port: 3000,
  roles: [
    # {<AtomName>, <Module>, <Initial Args>, <InstanceCount>}
    {:test, Beethoven.TestRole, [arg1: "arg1"], 2},
    {:testd, Beethoven.TestdRole, [arg1: "arg1"], 2}
  ]
```

This configuration uses the 2 test servers, `Beethoven.TestRole` and `Beethoven.TestdRole`.

Lets break down the configuration as a whole:

- `:use_az_net` -> Defines whether we should monitor Azure IMDS for changes. Used for Spot VMSS.
- `:cluster_net` -> Network name for the target cluster. Defaults to `127.0.0.0` if not defined above.
- `:cluster_net_mask` -> Subnet mask for the target cluster network.
- `:listener_port` -> Port used by `Beethoven.Locator` and `Beethoven.BeaconServer` for node discovery.
- `:roles` -> List of roles that Beethoven should monitor. Defaults to 'no roles' if left undefined.

### Role definition

Defining a role for Beethoven to track uses this following schema:

```elixir
# {<AtomName>, <Module>, <Initial Args>, <InstanceCount>}
{:test, Beethoven.TestRole, [arg1: "arg1"], 2}
```

- `AtomName` -> Friendly name for the Role within the Beethoven Cluster. Should be unique among the other defined roles.
- `Module` -> An OTP compliant server that will be used to spawn the role on creation.
- `Initial Args` -> Arguments that will be fed into the role on creation. Arguments will be input to the `start_link/2` function for the provided OTP compliant module.
- `InstanceCount` -> The number of instances needed for this role across the cluster.

> **Notes on `InstanceCount`**
>
> - Nodes in the cluster will only ever run one single instance of a role.
> - If you need this role on all nodes in the cluster, consider just adding it to your applications supervisor tree directly. You will receive no benefit from the Role assignment.
> - The number is maintained as nodes join and leave the cluster.

Now, once you start your Mix Application, your role should spawn once `Beethoven.RoleServer` has initialized.


# Any issues?
Please run your app with the environmental variable `MIX_ENV` set to `dev`, and create an issue on the [Github repo for Beethoven](https://github.com/jimurrito/beethoven).

