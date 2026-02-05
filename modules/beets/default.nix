{
  sharedHomeModule = { pkgs, ... }: {
    home.packages = [ pkgs.unflac ];

    programs.beets = {
      enable = true;
      settings = {
        plugins = [
          "badfiles"
          "scrub"
          "chroma"
          "replaygain"
          "albumtypes"
          "spotify"
          "deezer"
          "lastgenre"
          "discogs"
          "fetchart"
          "embedart"
          "lyrics"
          "missing"
          "info"
          "inline"
          "ftintitle"
          "unimported"
        ];

        embedart = {
          remove_art_file = true;
        };

        lyrics = {
          synced = true;
        };

        replaygain = {
          overwrite = true;
          per_disc = true;
        };

        lastgenre = {
          count = 5;
          source = "track";
        };

        chroma = {
          auto = true;
          source_weight = 0.1;
        };

        discogs = {
          append_style_genre = true;
          source_weight = 0.2;
        };

        spotify.source_weight = 0.3;
        deezer.source_weight = 0.4;

        item_fields = {
          multidisc = "1 if disctotal > 1 else 0";
          first_genre = "genre.split(', ')[0]";
        };

        import = {
          set_fields = {
            albumartist = "%first{%first{$albumartists,1,0,␀},1,0,\\}";
          };
        };

        paths = {
          default = "$albumartist/$album ($year)/%if{$multidisc,$disc - }\${track}. $title";
        };

        asciify_paths = true;
        per_disc_numbering = true;
        directory = "/media/tower/media/music";
      };
    };
  };
}
