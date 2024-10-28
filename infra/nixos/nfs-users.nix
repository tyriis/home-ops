{ pkgs, config, ... }:

{
  users.users.alex = {
    uid = 1002;
    isNormalUser = false;
    createHome = false;
  };

  users.users.dominik = {
    uid = 1003;
    isNormalUser = false;
    createHome = false;
  };

  users.users.kube = {
    uid = 1004;
    isNormalUser = false;
    createHome = false;
  };
}
