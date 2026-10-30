{ lib, pkgs, ... }:
let
  inherit (builtins) length toJSON;

  target = expr: legendFormat: { inherit expr legendFormat; };

  panel =
    type:
    {
      title,
      unit ? "short",
      targets,
      w ? 12,
      h ? 8,
      extra ? { },
    }:
    {
      inherit
        type
        title
        w
        h
        ;
      fieldConfig.defaults.unit = unit;
      targets = lib.imap0 (i: t: t // { refId = builtins.substring i 1 "ABCDEFGH"; }) targets;
    }
    // extra;

  timeseries = panel "timeseries";
  stat =
    args:
    panel "stat" (
      {
        w = 6;
        h = 4;
      }
      // args
    );

  limitPercent = {
    unit = "percent";
    min = 0;
    max = 100;
  };

  instantTable =
    {
      title,
      unit ? "short",
      expr,
      columns,
    }:
    panel "table" {
      inherit title unit;
      w = 24;
      targets = [
        {
          inherit expr;
          legendFormat = "";
          instant = true;
          format = "table";
        }
      ];
      extra.transformations = [
        {
          id = "filterFieldsByName";
          options.include.names = columns;
        }
      ];
    };

  # Flows panels left to right, wrapping onto a new row when the 24-column grid is full.
  layout =
    panels:
    (lib.foldl'
      (
        acc: p:
        let
          fits = acc.x + p.w <= 24;
          x = if fits then acc.x else 0;
          y = if fits then acc.y else acc.y + acc.rowHeight;
        in
        {
          x = x + p.w;
          inherit y;
          rowHeight = if fits then lib.max acc.rowHeight p.h else p.h;
          panels = acc.panels ++ [
            (
              removeAttrs p [
                "w"
                "h"
              ]
              // {
                id = length acc.panels + 1;
                gridPos = {
                  inherit x y;
                  inherit (p) w h;
                };
              }
            )
          ];
        }
      )
      {
        x = 0;
        y = 0;
        rowHeight = 0;
        panels = [ ];
      }
      panels
    ).panels;

  dashboard = uid: title: panels: {
    inherit uid title;
    tags = [ "spike" ];
    time = {
      from = "now-6h";
      to = "now";
    };
    refresh = "30s";
    panels = layout panels;
  };

  rate = metric: "rate(${metric}[$__rate_interval])";

  systemdService = ''id=~"/system.slice/.+[.]service"'';
  unitName = expr: ''label_replace(${expr}, "unit", "$1", "id", "/system.slice/(.+)")'';
  container = ''name!=""'';

  tokens = "claude_code_token_usage_tokens_total";
  cost = "claude_code_cost_usage_USD_total";
  workingSessions = "count by (job, session_id) (increase(${tokens}[5m]) > 0)";

  personalEmail = "aaron@cute.engineer";
  byAccount =
    expr:
    let
      everyAccountAsWork = ''label_replace(${expr}, "account", "work", "user_email", ".+")'';
    in
    ''label_replace(${everyAccountAsWork}, "account", "personal", "user_email", "${
      builtins.replaceStrings [ "." ] [ "[.]" ] personalEmail
    }")'';
  workingSessionsByAccount = "count by (account) (${byAccount "count by (user_email, session_id) (increase(${tokens}[5m]) > 0)"})";
  sumByAccount = expr: "sum by (account) (${byAccount expr})";

  inRange = by: metric: "sum by (${by}) (increase(${metric}[$__range])) > 0";

  backlogic = {
    type = "yesoreyeram-infinity-datasource";
    uid = "backlogic";
  };
  ticketsFrom = url: selector: columns: {
    datasource = backlogic;
    type = "json";
    source = "url";
    parser = "backend";
    format = "table";
    inherit url;
    url_options.method = "GET";
    root_selector = selector;
    columns = lib.mapAttrsToList (
      text: column:
      {
        inherit text;
        type = "string";
      }
      // column
    ) columns;
  };
  tickets = ticketsFrom "/api/snapshot";
  doneTickets = ticketsFrom "/api/done?from=\${__from}&to=\${__to}";
  countTickets = filter: tickets "$count(tickets[${filter}])" { };
  doneInRange = filter: "$append([], tickets[${filter}])";
  resolution = name: ''resolution = "${name}"'';
  resolutionColors = {
    met = "green";
    partly-met = "yellow";
    not-met = "red";
    rejected = "purple";
    unknown = "text";
  };
  resolutions = lib.attrNames resolutionColors;
  claimedTickets = countTickets ''state = "claimed"'';
  doneTicket = {
    doneAt = {
      selector = "doneAt";
      type = "timestamp";
    };
    id.selector = "id";
  };
  spendColumns =
    lib.mapAttrs
      (_: selector: {
        inherit selector;
        type = "number";
      })
      {
        tokens = "spend.tokens";
        minutes = "spend.minutes";
        cost = "spend.dollars";
      };

  ticketHistogram =
    {
      title,
      unit ? "short",
      column,
    }:
    panel "histogram" {
      inherit title unit;
      targets = [ (doneTickets (doneInRange "true") { tickets = column; }) ];
      extra = {
        datasource = backlogic;
        fieldConfig.defaults.unit = unit;
      };
    };

  tally =
    args:
    stat (
      args
      // {
        extra.fieldConfig.defaults = {
          unit = args.unit or "short";
          color = {
            mode = "fixed";
            fixedColor = "green";
          };
        };
      }
    );

  ticketStat =
    { title, target }:
    tally {
      inherit title;
      targets = [ target ];
    }
    // {
      datasource = backlogic;
    };

  dashboards = {
    hardware = dashboard "spike-hardware" "Spike / Hardware" [
      (stat {
        title = "Uptime";
        unit = "s";
        targets = [ (target "time() - node_boot_time_seconds" "uptime") ];
      })
      (stat {
        title = "CPU";
        unit = "percentunit";
        targets = [ (target "1 - avg(${rate ''node_cpu_seconds_total{mode="idle"}''})" "cpu") ];
      })
      (stat {
        title = "Memory";
        unit = "percentunit";
        targets = [ (target "1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes" "memory") ];
      })
      (stat {
        title = "Root disk";
        unit = "percentunit";
        targets = [
          (target ''1 - node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}'' "disk")
        ];
      })
      (timeseries {
        title = "CPU by mode";
        unit = "percentunit";
        targets = [
          (target "avg by (mode) (${rate ''node_cpu_seconds_total{mode!="idle"}''})" "{{mode}}")
        ];
      })
      (timeseries {
        title = "Load";
        targets = [
          (target "node_load1" "1m")
          (target "node_load5" "5m")
          (target "node_load15" "15m")
          (target ''count(node_cpu_seconds_total{mode="idle"})'' "cores")
        ];
      })
      (timeseries {
        title = "Memory";
        unit = "bytes";
        targets = [
          (target "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes" "used")
          (target "node_memory_Buffers_bytes + node_memory_Cached_bytes" "cache")
          (target "node_memory_SwapTotal_bytes - node_memory_SwapFree_bytes" "swap")
        ];
      })
      (timeseries {
        title = "Temperatures";
        unit = "celsius";
        targets = [
          (target "node_hwmon_temp_celsius * on (host, chip) group_left (chip_name) node_hwmon_chip_names" "{{host}} {{chip_name}} {{sensor}}")
        ];
      })
      (timeseries {
        title = "Disk throughput";
        unit = "Bps";
        targets = [
          (target (rate "node_disk_read_bytes_total") "{{device}} read")
          (target (rate "node_disk_written_bytes_total") "{{device}} write")
        ];
      })
      (timeseries {
        title = "Disk busy";
        unit = "percentunit";
        targets = [ (target (rate "node_disk_io_time_seconds_total") "{{device}}") ];
      })
      (timeseries {
        title = "Filesystem usage";
        unit = "percentunit";
        targets = [
          (target ''1 - node_filesystem_avail_bytes{fstype=~"ext4|vfat"} / node_filesystem_size_bytes{fstype=~"ext4|vfat"}'' "{{mountpoint}}")
        ];
      })
      (timeseries {
        title = "Network";
        unit = "Bps";
        targets = [
          (target (rate ''node_network_receive_bytes_total{device!="lo"}'') "{{device}} rx")
          (target (rate ''node_network_transmit_bytes_total{device!="lo"}'') "{{device}} tx")
        ];
      })
    ];

    services = dashboard "spike-services" "Spike / Services" [
      (stat {
        title = "Failed units";
        targets = [
          (target ''count(node_systemd_unit_state{state="failed"} == 1) or vector(0)'' "failed")
        ];
      })
      (stat {
        title = "Running processes";
        targets = [ (target "node_procs_running" "running") ];
      })
      (stat {
        title = "Blocked processes";
        targets = [ (target "node_procs_blocked" "blocked") ];
      })
      (stat {
        title = "Forks";
        unit = "ops";
        targets = [ (target (rate "node_forks_total") "forks") ];
      })
      (instantTable {
        title = "Units in failed state";
        expr = ''node_systemd_unit_state{state="failed"} == 1'';
        columns = [
          "name"
          "type"
        ];
      })
      (timeseries {
        title = "CPU by service (cores)";
        targets = [
          (target (unitName (rate "container_cpu_usage_seconds_total{${systemdService}}")) "{{unit}}")
        ];
      })
      (timeseries {
        title = "Memory by service";
        unit = "bytes";
        targets = [
          (target (unitName "container_memory_working_set_bytes{${systemdService}}") "{{unit}}")
        ];
      })
    ];

    containers = dashboard "spike-containers" "Spike / Containers" [
      (stat {
        title = "Running containers";
        targets = [ (target "count(container_start_time_seconds{${container}}) or vector(0)" "running") ];
      })
      (instantTable {
        title = "Container uptime";
        unit = "s";
        expr = "time() - container_start_time_seconds{${container}}";
        columns = [
          "name"
          "image"
          "Value"
        ];
      })
      (timeseries {
        title = "CPU (cores)";
        targets = [
          (target "sum by (name) (${rate "container_cpu_usage_seconds_total{${container}}"})" "{{name}}")
        ];
      })
      (timeseries {
        title = "Memory";
        unit = "bytes";
        targets = [ (target "container_memory_working_set_bytes{${container}}" "{{name}}") ];
      })
      (timeseries {
        title = "Network";
        unit = "Bps";
        targets = [
          (target "sum by (name) (${rate "container_network_receive_bytes_total{${container}}"})" "{{name}} rx")
          (target "sum by (name) (${rate "container_network_transmit_bytes_total{${container}}"})" "{{name}} tx")
        ];
      })
      (timeseries {
        title = "Disk I/O";
        unit = "Bps";
        targets = [
          (target "sum by (name) (${rate "container_fs_reads_bytes_total{${container}}"})" "{{name}} read")
          (target "sum by (name) (${rate "container_fs_writes_bytes_total{${container}}"})" "{{name}} write")
        ];
      })
    ];

    claude = dashboard "spike-claude" "Spike / Claude" [
      (stat {
        title = "Session limit used";
        extra.fieldConfig.defaults = limitPercent;
        targets = [ (target ''claude_limit_percent{kind="session"}'' "{{account}}") ];
      })
      (stat {
        title = "Session limit resets";
        unit = "dateTimeFromNow";
        targets = [ (target ''claude_limit_resets_at_seconds{kind="session"} * 1000'' "{{account}}") ];
      })
      (stat {
        title = "Weekly limit used";
        extra.fieldConfig.defaults = limitPercent;
        targets = [ (target ''claude_limit_percent{kind="weekly_all"}'' "{{account}}") ];
      })
      (stat {
        title = "Weekly limit resets";
        unit = "dateTimeFromNow";
        targets = [ (target ''claude_limit_resets_at_seconds{kind="weekly_all"} * 1000'' "{{account}}") ];
      })
      (timeseries {
        title = "Plan limits used";
        extra.fieldConfig.defaults = limitPercent;
        w = 18;
        targets = [ (target "claude_limit_percent" "{{account}} {{kind}} {{model}}") ];
      })
      (stat {
        title = "Plan limits age";
        h = 8;
        targets = [
          (target ''label_replace(time() - node_textfile_mtime_seconds{file=~".*/claude-limits-.*[.]prom"}, "account", "$1", "file", ".*/claude-limits-(.*)[.]prom")'' "{{account}}")
        ];
        extra.fieldConfig.defaults = {
          unit = "s";
          thresholds = {
            mode = "absolute";
            steps = [
              {
                color = "green";
                value = null;
              }
              {
                color = "red";
                value = 1800;
              }
            ];
          };
        };
      })
      (stat {
        title = "Working sessions";
        targets = [ (target "${workingSessionsByAccount} or on () vector(0)" "{{account}}") ];
      })
      (ticketStat {
        title = "Claimed backlogic tickets";
        target = claimedTickets;
      })
      (stat {
        title = "Tokens in range";
        targets = [ (target (sumByAccount "increase(${tokens}[$__range])") "{{account}}") ];
      })
      (stat {
        title = "API-equivalent cost in range";
        unit = "currencyUSD";
        targets = [ (target (sumByAccount "increase(${cost}[$__range])") "{{account}}") ];
      })
      (stat {
        title = "Sessions in range";
        h = 8;
        targets = [
          (target "count by (account) (${byAccount (inRange "user_email, session_id" tokens)})" "{{account}}")
        ];
      })
      (timeseries {
        title = "Working sessions by account";
        w = 18;
        targets = [ (target workingSessionsByAccount "{{account}}") ];
      })
      (timeseries {
        title = "Tokens per minute by account";
        targets = [ (target "${sumByAccount (rate tokens)} * 60" "{{account}}") ];
      })
      (timeseries {
        title = "API-equivalent cost per hour by account";
        unit = "currencyUSD";
        targets = [ (target "${sumByAccount (rate cost)} * 3600" "{{account}}") ];
      })
      (timeseries {
        title = "Working sessions by source";
        targets = [ (target "count by (job) (${workingSessions})" "{{job}}") ];
      })
      (timeseries {
        title = "Sessions actively working by source";
        targets = [ (target "sum by (job) (${rate "claude_code_active_time_seconds_total"})" "{{job}}") ];
      })
      (timeseries {
        title = "Tokens per minute by type";
        targets = [ (target "sum by (type) (${rate tokens}) * 60" "{{type}}") ];
      })
      (timeseries {
        title = "Tokens per minute by source";
        targets = [ (target "sum by (job) (${rate tokens}) * 60" "{{job}}") ];
      })
      (timeseries {
        title = "Tokens per minute by model";
        targets = [ (target "sum by (model) (${rate tokens}) * 60" "{{model}}") ];
      })
      (timeseries {
        title = "API-equivalent cost per hour by source";
        unit = "currencyUSD";
        targets = [ (target "sum by (job) (${rate cost}) * 3600" "{{job}}") ];
      })
    ];

    agents =
      dashboard "spike-agents" "Spike / Backlogic" [
        (ticketStat {
          title = "Open tickets";
          target = countTickets ''state != "done"'';
        })
        (ticketStat {
          title = "Met in range";
          target = doneTickets "$count(${doneInRange (resolution "met")})" { };
        })
        (ticketStat {
          title = "Short of met in range";
          target = doneTickets "$count(${doneInRange ''resolution != "met"''})" { };
        })
        (ticketStat {
          title = "Claimed tickets";
          target = claimedTickets;
        })
        (panel "timeseries" {
          title = "Tickets done per day";
          w = 24;
          targets = map (name: doneTickets (doneInRange (resolution name)) doneTicket) resolutions;
          extra = {
            datasource = backlogic;
            fieldConfig = {
              defaults.custom = {
                drawStyle = "bars";
                fillOpacity = 80;
                stacking.mode = "normal";
              };
              overrides = lib.imap0 (i: name: {
                matcher = {
                  id = "byFrameRefID";
                  options = builtins.substring i 1 "ABCDEFGH";
                };
                properties = [
                  {
                    id = "displayName";
                    value = lib.replaceStrings [ "-" ] [ " " ] name;
                  }
                  {
                    id = "color";
                    value = {
                      mode = "fixed";
                      fixedColor = resolutionColors.${name};
                    };
                  }
                ];
              }) resolutions;
            };
            transformations = [
              {
                id = "formatTime";
                options = {
                  timeField = "doneAt";
                  outputFormat = "YYYY-MM-DD";
                };
              }
              {
                id = "groupBy";
                options.fields = {
                  doneAt = {
                    aggregations = [ ];
                    operation = "groupby";
                  };
                  id = {
                    aggregations = [ "count" ];
                    operation = "aggregate";
                  };
                };
              }
              {
                id = "convertFieldType";
                options.conversions = [
                  {
                    targetField = "doneAt";
                    destinationType = "time";
                    dateFormat = "YYYY-MM-DD";
                  }
                ];
              }
            ];
          };
        })
        (ticketHistogram {
          title = "Tokens per ticket done in range";
          column = spendColumns.tokens;
        })
        (ticketHistogram {
          title = "Claude time per ticket done in range";
          unit = "m";
          column = spendColumns.minutes;
        })
        (panel "table" {
          title = "Spend per ticket done in range";
          w = 24;
          targets = [
            (doneTickets (doneInRange "true") (
              {
                ticket.selector = "id";
                project.selector = "project";
                title.selector = "title";
                resolution.selector = "resolution";
              }
              // spendColumns
            ))
          ];
          extra = {
            datasource = backlogic;
            transformations = [
              {
                id = "organize";
                options.indexByName = lib.listToAttrs (
                  lib.imap0 (index: name: lib.nameValuePair name index) [
                    "ticket"
                    "project"
                    "title"
                    "resolution"
                    "tokens"
                    "minutes"
                    "cost"
                  ]
                );
              }
              {
                id = "sortBy";
                options.sort = [
                  {
                    field = "tokens";
                    desc = true;
                  }
                ];
              }
            ];
            fieldConfig = {
              defaults = { };
              overrides =
                lib.mapAttrsToList
                  (name: unit: {
                    matcher = {
                      id = "byName";
                      options = name;
                    };
                    properties = [
                      {
                        id = "unit";
                        value = unit;
                      }
                    ];
                  })
                  {
                    tokens = "short";
                    minutes = "m";
                    cost = "currencyUSD";
                  };
            };
          };
        })
      ]
      // {
        time = {
          from = "now-7d";
          to = "now";
        };
        refresh = "5m";
      };
  };

  dashboardsDir = pkgs.linkFarm "grafana-dashboards" (
    lib.mapAttrsToList (name: d: {
      name = "${name}.json";
      path = pkgs.writeText "${name}.json" (toJSON d);
    }) dashboards
  );
in
{
  services.grafana.provision.dashboards.settings.providers = [
    {
      name = "spike";
      options.path = dashboardsDir;
    }
  ];
}
