{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib }: let
  tf = import ./lib.nix {
    inherit lib;
  };
in tf // {
  terraformContext = tf.terraformContext pkgs;
  hclDir = args: tf.hclDir ({
    inherit pkgs;
  } // args);
  run = lib.mapAttrs (_: lib.flip pkgs.callPackage { }) tf.run;
}
