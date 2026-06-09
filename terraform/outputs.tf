output "wazuh_public_ip" {
  description = "IP publique du serveur Wazuh (dashboard + SSH)"
  value       = aws_instance.wazuh.public_ip
}

output "victim_public_ip" {
  description = "IP publique de la machine cible (admin SSH)"
  value       = aws_instance.victim.public_ip
}

output "victim_private_ip" {
  description = "IP privee de la cible (cible du brute force depuis le serveur Wazuh)"
  value       = aws_instance.victim.private_ip
}

output "cloudtrail_bucket" {
  description = "Nom du bucket CloudTrail (a mettre dans la conf Wazuh)"
  value       = aws_s3_bucket.cloudtrail.id
}

output "victim_data_bucket" {
  description = "Bucket cible du scenario d'exposition publique"
  value       = aws_s3_bucket.victim_data.id
}
