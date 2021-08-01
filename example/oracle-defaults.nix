{ ... }: {
  config = {
    variables = {
      oci_region.value.shellCommand = "bitw get tokens/oracle-tfnix -f region";
      oci_tenancy.value.shellCommand = "bitw get tokens/oracle-tfnix -f tenancy";
      oci_user.value.shellCommand = "bitw get tokens/oracle-tfnix -f user";
      oci_privkey.value.shellCommand = "bitw get tokens/oracle-tfnix -f notes";
      oci_fingerprint.value.shellCommand = "bitw get tokens/oracle-tfnix -f fingerprint";
      oci_bucket.value.shellCommand = "bitw get tokens/oracle-tfnix -f bucket_name";
      oci_compartment.value.shellCommand = "bitw get tokens/oracle-tfnix -f compartment";
    };
  };
}
