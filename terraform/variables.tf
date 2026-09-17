variable "project_name" {
    type = string
    default = "terraform-aks-pipeline"
}

variable "location" {
  type = string
  default     = "West Europe"
}

variable "node_count" {
  type    = number
  default = 1
}

variable "node_vm_size" {
  type    = string
  default = "Standard_D2s_v3"
}

