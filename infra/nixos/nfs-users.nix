{ pkgs, config, ... }:

{
  users.users.alex = {
    uid = 1002;
    isSystemUser = true;
    createHome = false;
  };

  users.users.dominik = {
    uid = 1003;
    isSystemUser = true;
    createHome = false;
  };

  users.users.kube = {
    uid = 1004;
    isSystemUser = true;
    createHome = false;
  };
}
