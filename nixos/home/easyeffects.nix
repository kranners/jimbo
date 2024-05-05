{
  config,
  pkgs,
  lib,
  inputs,
  ...
}: {
  services.easyeffects = {
    enable = false;
    preset = "oratory1990";
  };

  xdg.configFile.easyeffects = {
    enable = false;
    target = "./easyeffects/output/oratory1990.json";

    text = ''
      {
        "output": {
          "blocklist": [],
          "equalizer#0": {
            "balance": 0.0,
            "bypass": false,
            "input-gain": -7.13,
            "left": {
              "band0": {
                "frequency": 105.0,
                "gain": 9.100000381469727,
                "mode": "APO (DR)",
                "mute": false,
                "q": 0.699999988079071,
                "slope": "x1",
                "solo": false,
                "type": "Lo-shelf",
                "width": 4.0
              },
              "band1": {
                "frequency": 55.599998474121094,
                "gain": -2.0,
                "mode": "APO (DR)",
                "mute": false,
                "q": 0.9300000071525574,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band2": {
                "frequency": 69.4000015258789,
                "gain": -3.200000047683716,
                "mode": "APO (DR)",
                "mute": false,
                "q": 0.30000001192092896,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band3": {
                "frequency": 141.1999969482422,
                "gain": 0.8999999761581421,
                "mode": "APO (DR)",
                "mute": false,
                "q": 1.809999942779541,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band4": {
                "frequency": 971.9000244140625,
                "gain": -1.5,
                "mode": "APO (DR)",
                "mute": false,
                "q": 1.9199999570846558,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band5": {
                "frequency": 1240.699951171875,
                "gain": -0.20000000298023224,
                "mode": "APO (DR)",
                "mute": false,
                "q": 3.240000009536743,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band6": {
                "frequency": 1771.5999755859375,
                "gain": 0.5,
                "mode": "APO (DR)",
                "mute": false,
                "q": 5.289999961853027,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band7": {
                "frequency": 2188.5,
                "gain": 1.899999976158142,
                "mode": "APO (DR)",
                "mute": false,
                "q": 2.630000114440918,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band8": {
                "frequency": 9460.599609375,
                "gain": 3.200000047683716,
                "mode": "APO (DR)",
                "mute": false,
                "q": 1.0299999713897705,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band9": {
                "frequency": 10000.0,
                "gain": -4.599999904632568,
                "mode": "APO (DR)",
                "mute": false,
                "q": 0.699999988079071,
                "slope": "x1",
                "solo": false,
                "type": "Hi-shelf",
                "width": 4.0
              }
            },
            "mode": "IIR",
            "num-bands": 10,
            "output-gain": 0.0,
            "pitch-left": 0.0,
            "pitch-right": 0.0,
            "right": {
              "band0": {
                "frequency": 105.0,
                "gain": 9.100000381469727,
                "mode": "APO (DR)",
                "mute": false,
                "q": 0.699999988079071,
                "slope": "x1",
                "solo": false,
                "type": "Lo-shelf",
                "width": 4.0
              },
              "band1": {
                "frequency": 55.599998474121094,
                "gain": -2.0,
                "mode": "APO (DR)",
                "mute": false,
                "q": 0.9300000071525574,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band2": {
                "frequency": 69.4000015258789,
                "gain": -3.200000047683716,
                "mode": "APO (DR)",
                "mute": false,
                "q": 0.30000001192092896,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band3": {
                "frequency": 141.1999969482422,
                "gain": 0.8999999761581421,
                "mode": "APO (DR)",
                "mute": false,
                "q": 1.809999942779541,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band4": {
                "frequency": 971.9000244140625,
                "gain": -1.5,
                "mode": "APO (DR)",
                "mute": false,
                "q": 1.9199999570846558,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band5": {
                "frequency": 1240.699951171875,
                "gain": -0.20000000298023224,
                "mode": "APO (DR)",
                "mute": false,
                "q": 3.240000009536743,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band6": {
                "frequency": 1771.5999755859375,
                "gain": 0.5,
                "mode": "APO (DR)",
                "mute": false,
                "q": 5.289999961853027,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band7": {
                "frequency": 2188.5,
                "gain": 1.899999976158142,
                "mode": "APO (DR)",
                "mute": false,
                "q": 2.630000114440918,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band8": {
                "frequency": 9460.599609375,
                "gain": 3.200000047683716,
                "mode": "APO (DR)",
                "mute": false,
                "q": 1.0299999713897705,
                "slope": "x1",
                "solo": false,
                "type": "Bell",
                "width": 4.0
              },
              "band9": {
                "frequency": 10000.0,
                "gain": -4.599999904632568,
                "mode": "APO (DR)",
                "mute": false,
                "q": 0.699999988079071,
                "slope": "x1",
                "solo": false,
                "type": "Hi-shelf",
                "width": 4.0
              }
            },
            "split-channels": false
          },
          "plugins_order": ["equalizer#0"]
        }
      }
    '';
  };
}
