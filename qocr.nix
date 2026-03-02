{
  lib,
  stdenvNoCC,

  qt6,
  qocrd,
  wl-clipboard,
  quickshell,
}:
stdenvNoCC.mkDerivation {
  pname = "qocr";
  version = "0.1.0";
  src = lib.cleanSourceWith {
    src = ./.;
    filter =
      path: type:
      (builtins.any (prefix: lib.path.hasPrefix (./. + prefix) (/. + path)) [
        /shell.qml
        /shell
      ]);
  };

  nativeBuildInputs = [
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    qt6.qtbase
  ];

  installPhase = ''
    mkdir -p $out/share/qocr $out/bin
    cp -r . $out/share/qocr
    ln -s ${quickshell}/bin/qs $out/bin/qocr
  '';

  preFixup = ''
    qtWrapperArgs+=(
      --prefix PATH : ${
        lib.makeBinPath [
          qocrd
          wl-clipboard
          quickshell
        ]
      }
      --add-flags "-p $out/share/qocr"
    )
  '';

  meta = {
    description = "Wayland OCR overlay focused on Japanese text, built with Quickshell.";
    homepage = "https://github.com/werapea/qocr";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "qocr";
  };
}
