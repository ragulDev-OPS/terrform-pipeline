output "key_name" {
  value       = try(aws_key_pair.imported[0].key_name, "")
  description = "Name of SSH key"
}