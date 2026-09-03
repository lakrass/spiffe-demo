{
  inputs = { nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable"; };

  outputs = { self, nixpkgs }:
    let
      supportedSystems =
        [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSupportedSystem = f:
        nixpkgs.lib.genAttrs supportedSystems (system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          });
    in {
      devShells = forEachSupportedSystem ({ pkgs }:
        let
          # wrap helm to include plugins for helmfile
          wrapped-kubernetes-helm = with pkgs;
            wrapHelm kubernetes-helm {
              plugins = with kubernetes-helmPlugins; [
                helm-secrets
                helm-diff
                helm-s3
                helm-git
              ];
            };

          # pass plugins to helmfile-wrapped package
          wrapped-helmfile = pkgs.helmfile-wrapped.override {
            inherit (wrapped-kubernetes-helm) pluginsDir;
          };

        in {
          default = pkgs.mkShell {
            packages = with pkgs; [ kubectl openssl ];

            buildInputs = [ wrapped-kubernetes-helm wrapped-helmfile ];
          };
        });
    };
}
