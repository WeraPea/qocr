{
  lib,
  buildPythonApplication,
  setuptools,
  pillow,
  protobuf,

  grim,
  slurp,
}:
buildPythonApplication {
  pname = "qocrd";
  version = "0.1.0";
  src = ./..;

  pyproject = true;
  build-system = [ setuptools ];

  propagatedBuildInputs = [
    pillow
    grim
    slurp
    protobuf
  ];

  meta = {
    mainProgram = "qocrd";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
  };
}
