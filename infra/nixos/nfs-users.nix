{ pkgs, config, ... }:

{
  users.users.alex = {
    uid = 1002;
    isNormalUser = true;
    createHome = false;
  };

  users.users.dominik = {
    uid = 1003;
    isNormalUser = true;
    createHome = false;
  };

  users.users.kube = {
    uid = 1004;
    isNormalUser = true;
    createHome = false;
  };
}
