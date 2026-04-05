self:
{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.services.qocr;
  jsonFormat = pkgs.formats.json { };
  qocr = self.packages.${pkgs.stdenv.hostPlatform.system}.qocr;
in
{
  options.services.qocr = {
    enable = lib.mkEnableOption "qocr";

    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          yomitan = {
            fetchAudio = true;
          };
        };
      '';
      description = "Configuration written to $XDG_CONFIG_HOME/qocr/config.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ qocr ];

    xdg.configFile."qocr/config.json".source = jsonFormat.generate "qocr-config.json" cfg.settings;

    systemd.user.services.qocr = {
      Unit = {
        Description = "qocr";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = lib.getExe qocr;
        Restart = "on-failure";
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
