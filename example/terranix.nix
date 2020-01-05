{ ... }: {
  resources = {
    nginx = {
      provider = "hcloud";
      type = "server";
      inputs = {
        image  = "debian-10";
        server_type = "cx11";
        backups = false;
      };
    };
    test = {
      provider = "hcloud";
      type = "server";
      inputs = {
        image  = "debian-9";
        server_type = "cx11";
        backups = true;
      };
    };
  };
}
