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
  liveSessions = "count by (job, session_id) (claude_code_session_count_total)";
  activeTime = "claude_code_active_time_seconds_total";
  threads = ''job=~"discord-threads|slack-threads"'';

  inRange = by: metric: "sum by (${by}) (increase(${metric}[$__range])) > 0";
  perIssue = metric: inRange "issue" ''${metric}{job="workaholic",issue!=""}'';
  perSession = job: metric: inRange "session_id" ''${metric}{job="${job}"}'';

  instantTableTarget = expr: {
    inherit expr;
    legendFormat = "";
    instant = true;
    format = "table";
  };

  named =
    names:
    lib.mapAttrsToList (refId: displayName: {
      matcher = {
        id = "byFrameRefID";
        options = refId;
      };
      properties = [
        {
          id = "displayName";
          value = displayName;
        }
      ];
    }) names;

  histogram =
    {
      title,
      unit ? "short",
      targets,
      names ? { },
    }:
    panel "histogram" {
      inherit title unit;
      targets = map instantTableTarget targets;
      extra.fieldConfig = {
        defaults.unit = unit;
        overrides = named names;
      };
    };

  github = {
    type = "grafana-github-datasource";
    uid = "github";
  };
  workaholicRepos = [
    "kranners/bowerbird"
    "kranners/jimbo"
    "kranners/workaholic"
    "kranners/claude-slack-threads"
  ];
  issueTimeField = {
    created = 0;
    closed = 1;
  };
  issues = timeField: query: {
    datasource = github;
    queryType = "Issues";
    owner = "kranners";
    repository = "";
    options = {
      timeField = issueTimeField.${timeField};
      query = lib.concatMapStringsSep " " (repo: "repo:${repo}") workaholicRepos + " " + query;
    };
  };
  completed = "reason:completed";
  withoutChange = "is:closed -reason:completed";

  issueStat =
    {
      title,
      target,
      extra ? { },
    }:
    stat {
      inherit title;
      targets = [ target ];
      extra = {
        datasource = github;
        fieldConfig.defaults.noValue = "0";
        options.reduceOptions = {
          calcs = [ "count" ];
          fields = "/^number$/";
        };
      }
      // extra;
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
          (target "node_hwmon_temp_celsius * on (chip) group_left (chip_name) node_hwmon_chip_names" "{{chip_name}} {{sensor}}")
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
        targets = [ (target ''claude_limit_percent{kind="session"}'' "session") ];
      })
      (stat {
        title = "Session limit resets";
        unit = "dateTimeFromNow";
        targets = [ (target ''claude_limit_resets_at_seconds{kind="session"} * 1000'' "session") ];
      })
      (stat {
        title = "Weekly limit used";
        extra.fieldConfig.defaults = limitPercent;
        targets = [ (target ''claude_limit_percent{kind="weekly_all"}'' "weekly") ];
      })
      (stat {
        title = "Weekly limit resets";
        unit = "dateTimeFromNow";
        targets = [ (target ''claude_limit_resets_at_seconds{kind="weekly_all"} * 1000'' "weekly") ];
      })
      (timeseries {
        title = "Plan limits used";
        extra.fieldConfig.defaults = limitPercent;
        w = 18;
        targets = [ (target "claude_limit_percent" "{{kind}} {{model}}") ];
      })
      (stat {
        title = "Plan limits age";
        h = 8;
        targets = [
          (target ''time() - node_textfile_mtime_seconds{file=~".*/claude-limits[.]prom"}'' "age")
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
                value = 600;
              }
            ];
          };
        };
      })
      (stat {
        title = "Live sessions";
        targets = [ (target "count(${liveSessions}) or vector(0)" "sessions") ];
      })
      (stat {
        title = "Busy workaholic runners";
        targets = [
          (target ''count(node_systemd_unit_state{name=~"workaholic@.+",state="activating"} == 1) or vector(0)'' "runners")
        ];
      })
      (stat {
        title = "Tokens in range";
        targets = [ (target "sum(increase(${tokens}[$__range]))" "tokens") ];
      })
      (stat {
        title = "API-equivalent cost in range";
        unit = "currencyUSD";
        targets = [ (target "sum(increase(${cost}[$__range]))" "cost") ];
      })
      (timeseries {
        title = "Live sessions by source";
        targets = [ (target "count by (job) (${liveSessions})" "{{job}}") ];
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
      dashboard "spike-agents" "Spike / Workaholic and threads" [
        (issueStat {
          title = "Open issues";
          target = issues "created" "is:open";
          extra.timeFrom = "10y";
        })
        (issueStat {
          title = "Completed in range";
          target = issues "closed" completed;
        })
        (issueStat {
          title = "Closed without change in range";
          target = issues "closed" withoutChange;
        })
        (stat {
          title = "Issues worked in range";
          targets = [ (target "count(${perIssue tokens}) or vector(0)" "issues") ];
        })
        (panel "timeseries" {
          title = "Issues closed per day";
          w = 24;
          targets = [
            (issues "closed" completed)
            (issues "closed" withoutChange)
          ];
          extra = {
            datasource = github;
            fieldConfig = {
              defaults.custom = {
                drawStyle = "bars";
                fillOpacity = 80;
                stacking.mode = "normal";
              };
              overrides = named {
                A = "completed";
                B = "closed without change";
              };
            };
            transformations = [
              {
                id = "formatTime";
                options = {
                  timeField = "closed_at";
                  outputFormat = "YYYY-MM-DD";
                };
              }
              {
                id = "groupBy";
                options.fields = {
                  closed_at = {
                    aggregations = [ ];
                    operation = "groupby";
                  };
                  number = {
                    aggregations = [ "count" ];
                    operation = "aggregate";
                  };
                };
              }
              {
                id = "convertFieldType";
                options.conversions = [
                  {
                    targetField = "closed_at";
                    destinationType = "time";
                    dateFormat = "YYYY-MM-DD";
                  }
                ];
              }
            ];
          };
        })
        (histogram {
          title = "Tokens per issue";
          targets = [ (perIssue tokens) ];
        })
        (histogram {
          title = "Claude active time per issue";
          unit = "s";
          targets = [ (perIssue activeTime) ];
        })
        (panel "table" {
          title = "Tokens and time per issue";
          w = 24;
          targets = map instantTableTarget [
            (perIssue tokens)
            (perIssue activeTime)
            (perIssue cost)
          ];
          extra = {
            transformations = [
              {
                id = "merge";
                options = { };
              }
              {
                id = "organize";
                options = {
                  excludeByName.Time = true;
                  renameByName = {
                    "Value #A" = "tokens";
                    "Value #B" = "active time";
                    "Value #C" = "API-equivalent cost";
                  };
                };
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
                    "active time" = "s";
                    "API-equivalent cost" = "currencyUSD";
                  };
            };
          };
        })
        (stat {
          title = "Discord sessions in range";
          targets = [ (target "count(${perSession "discord-threads" tokens}) or vector(0)" "sessions") ];
        })
        (stat {
          title = "Slack sessions in range";
          targets = [ (target "count(${perSession "slack-threads" tokens}) or vector(0)" "sessions") ];
        })
        (stat {
          title = "Thread tokens in range";
          targets = [ (target "sum(increase(${tokens}{${threads}}[$__range]))" "tokens") ];
        })
        (stat {
          title = "Thread active time in range";
          unit = "s";
          targets = [ (target "sum(increase(${activeTime}{${threads}}[$__range]))" "time") ];
        })
        (histogram {
          title = "Tokens per thread session";
          targets = [
            (perSession "discord-threads" tokens)
            (perSession "slack-threads" tokens)
          ];
          names = {
            A = "discord-threads";
            B = "slack-threads";
          };
        })
        (histogram {
          title = "Claude active time per thread session";
          unit = "s";
          targets = [
            (perSession "discord-threads" activeTime)
            (perSession "slack-threads" activeTime)
          ];
          names = {
            A = "discord-threads";
            B = "slack-threads";
          };
        })
      ]
      // {
        time = {
          from = "now-30d";
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
