defmodule Beethoven.Quicknesia do
  @moduledoc """
  :mnesia.table_info(CoreTracker, :all)

  [
    access_mode: :read_write,
    active_replicas: [:"nodeX@127.0.0.1"],
    all_nodes: [:"nodeX@127.0.0.1"],
    arity: 4,
    attributes: [:node, :status, :last_change],
    checkpoints: [],
    commit_work: [{:subscribers, [], [#PID<0.373.0>]}],
    cookie: {{1751039904501037628, -576460752303423038, 1}, :"nodeX@127.0.0.1"},
    cstruct: {:cstruct, CoreTracker, :ordered_set, [:"nodeX@127.0.0.1"], [], [],
    [], 0, :read_write, false, [], [], false, CoreTracker,
    [:node, :status, :last_change], [], [], [],
    {{1751039904501037628, -576460752303423038, 1}, :"nodeX@127.0.0.1"},
    {{2, 0}, []}},
    disc_copies: [],
    disc_only_copies: [],
    external_copies: [],
    frag_properties: [],
    index: [],
    index_info: {:index, :ordered_set, []},
    load_by_force: false,
    load_node: :"nodeX@127.0.0.1",
    load_order: 0,
    load_reason: {:dumper, :create_table},
    local_content: false,
    majority: false,
    master_nodes: [],
    memory: 188,
    ram_copies: [:"nodeX@127.0.0.1"],
    record_name: CoreTracker,
    record_validation: {CoreTracker, 4, :ordered_set},
    size: 1,
    snmp: [],
    storage_properties: [],
    storage_type: :ram_copies,
    subscribers: [#PID<0.373.0>],
    type: :ordered_set,
    user_properties: [],
    version: {{2, 0}, []},
    where_to_commit: ["nodeX@127.0.0.1": :ram_copies],
    where_to_read: :"nodeX@127.0.0.1",
    where_to_wlock: {[:"nodeX@127.0.0.1"], false},
    where_to_write: [:"nodeX@127.0.0.1"],
    wild_pattern: {CoreTracker, :_, :_, :_}
  ]

  """
end
