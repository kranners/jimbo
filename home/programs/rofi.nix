{
  programs.rofi = {
    enable = true;

    location = "center";

    theme = {
      "*" = {
        selected-active-background = "#778C8B";
        selected-active-foreground = "#d1d6d7";
        selected-normal-background = "#7FA09D";
        selected-normal-foreground = "#d1d6d7";
        selected-urgent-background = "#8A9796";
        selected-urgent-foreground = "#d1d6d7";

        background-color = "#0f1214";
        background = "#0f1214";
        foreground = "#d1d6d7";
        border-color = "#0f1214";
        spacing = "2";
      };

      "#window" = {
        background-color = "#0f1214";
        border = "0";
        padding = "2.5ch";
      };

      "#mainbox" = {
        border = "0";
        padding = "0";
      };

      "#message" = {
        border = "2px 0px 0px";
        border-color = "@border-color";
        padding = "1px";
      };

      "#textbox" = {
        text-color = "#d1d6d7";
      };

      "#inputbar" = {
        children = "[ prompt,textbox-prompt-colon,entry,case-indicator ]";
      };

      "#textbox-prompt-colon" = {
        expand = false;
        str = ":";
        margin = "0px 0.3em 0em 0em";
        text-color = "#d1d6d7";
      };

      "#listview" = {
        fixed-height = "0";
        border = "2px 0px 0px";
        border-color = "@border-color";
        spacing = "2px";
        scrollbar = true;
        padding = "2px 0px 0px";
      };

      "#element" = {
        border = "0";
        padding = "1px";
      };

      "#element-text, element-icon" = {
        background-color = "inherit";
        text-color = "inherit";
      };

      "#element.normal.normal" = {
        background-color = "#0f1214";
        text-color = "#d1d6d7";
      };

      "#element.normal.urgent" = {
        background-color = "#778C8B";
        text-color = "#d1d6d7";
      };

      "#element.normal.active" = {
        background-color = "#7FA09D";
        text-color = "#d1d6d7";
      };

      "#element.selected.normal" = {
        background-color = "@selected-normal-background";
        text-color = "@selected-normal-foreground";
      };

      "#element.selected.urgent" = {
        background-color = "@selected-urgent-background";
        text-color = "@selected-urgent-foreground";
      };

      "#element.selected.active" = {
        background-color = "@selected-active-background";
        text-color = "@selected-active-foreground";
      };

      "#element.alternate.normal" = {
        background-color = "#0f1214";
        text-color = "#d1d6d7";
      };

      "#element.alternate.urgent" = {
        background-color = "#0f1214";
        text-color = "#d1d6d7";
      };

      "#element.alternate.active" = {
        background-color = "#0f1214";
        text-color = "#d1d6d7";
      };

      "#scrollbar" = {
        width = "4px";
        border = "0";
        handle-width = "8px";
        padding = "0";
      };

      "#sidebar" = {
        border = "2px 0px 0px";
        border-color = "@border-color";
      };

      "#button" = {
        text-color = "#d1d6d7";
      };

      "#button.selected" = {
        background-color = "@selected-normal-background";
        text-color = "@selected-normal-foreground";
      };

      "#inputbar" = {
        spacing = "0";
        text-color = "#d1d6d7";
        padding = "1px";
      };

      "#case-indicator" = {
        spacing = "0";
        text-color = "#d1d6d7";
      };

      "#entry" = {
        spacing = "0";
        text-color = "#d1d6d7";
      };

      "#prompt" = {
        spacing = "0";
        text-color = "#d1d6d7";
      };

      element = {
        spacing = "15px";
        padding = "8px";
        border-radius = "10px";
        background-color = "#0f1214";
        text-color = "#d1d6d7";
      };

      "element.normal.normal" = {
        background-color = "#0f1214";
        text-color = "#d1d6d7";
      };

      "element.selected.normal" = {
        background-color = "#d1d6d7";
        text-color = "#0f1214";
      };

      element-icon = {
        background-color = "transparent";
        text-color = "inherit";
        size = "32px";
      };

      element-text = {
        background-color = "transparent";
        text-color = "inherit";
        vertical-align = "0.5";
      };

      window = {
        width = "500px";

        border = "2px solid";
        border-color = "#d1d6d7";
        border-radius = "12px";

        background-color = "#0f1214";
        padding = "0px";
      };

      inputbar = {
        spacing = "10px";
        padding = "15px";
        border-radius = "20px";
        background-color = "#d1d6d7";
        text-color = "#0f1214";
        children = ["textbox-prompt-colon" "entry"];
      };

      textbox-prompt-colon = {
        expand = false;
        str = "";
        background-color = "inherit";
        text-color = "inherit";
        vertical-align = "0.5";
      };

      entry = {
        background-color = "inherit";
        text-color = "inherit";
        placeholder = "Search";
        placeholder-color = "inherit";
      };

      listview = {
        columns = "1";
        lines = "6";
        scrollbar = false;
        spacing = "10px";
        text-color = "#d1d6d7";
        background-color = "#0f1214";
      };
    };

    extraConfig = {
      show-icons = true;
    };
  };
}
