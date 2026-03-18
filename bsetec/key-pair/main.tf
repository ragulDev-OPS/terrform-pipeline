locals {
  enabled = module.this.enabled
  public_key_filename = format(
    "%s/%s",
    var.ssh_public_key_path,
    coalesce(var.ssh_public_key_file, join("", [module.this.id, var.public_key_extension]))
  )
}
resource "aws_key_pair" "imported" {
  count      = local.enabled && var.generate_ssh_key == false ? 1 : 0
  key_name   = module.this.id
  public_key = file(local.public_key_filename)
  tags       = module.this.tags
}