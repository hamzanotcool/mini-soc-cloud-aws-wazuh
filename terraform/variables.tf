variable "aws_region" {
  description = "Region AWS"
  type        = string
  default     = "eu-west-3" # Paris
}

variable "my_ip" {
  description = "Ton IP publique en CIDR (ex: 1.2.3.4/32). Recupere-la avec : curl ifconfig.me"
  type        = string
}

variable "wazuh_instance_type" {
  description = "Type d'instance pour le serveur Wazuh (8 Go RAM recommandes)"
  type        = string
  default     = "t3.large"
}

variable "key_name" {
  description = "Nom de la cle SSH a creer dans AWS"
  type        = string
  default     = "soc-key"
}
