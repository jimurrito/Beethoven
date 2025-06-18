import Config

config :beethoven,
  use_az_net: false,
  cluster_net: "127.0.0.0",
  cluster_net_mask: "29",
  listener_port: 3000,
  # Range below represents milliseconds
  common_random_backoff: 150..300,
  roles: [
    # {<AtomName>, <Module>, <Initial Args>, <InstanceCount>}
    {:test, Beethoven.TestRole, [arg1: "arg1"], 1}
  ]
