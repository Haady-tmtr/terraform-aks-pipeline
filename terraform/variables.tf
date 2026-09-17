variable "project_name" {
  type    = string
  default = "terraform-aks-pipeline"
}

variable "location" {
  type    = string
  default = "swedencentral"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "node_vm_size" {
  type    = string
  default = "standard_b2as_v2"
}

