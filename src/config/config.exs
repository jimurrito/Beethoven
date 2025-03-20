import Config

config :beethoven,
  cluster_net: "127.0.0.0",
  cluster_net_mask: "29",
  listener_port: 3000,
  roles: [
    # {<AtomName>, <Module>, <Initial Args>, <InstanceCount>}
    {:test, Beethoven.TestRole, [arg1: "arg1"], 1}
  ]
