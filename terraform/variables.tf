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


variable "github_owner" {
  type    = string
  default = "Haady-tmtr"
}

variable "github_owner_id" {
  type    = string
  default = "194427639"
}

variable "github_repo" {
  type    = string
  default = "terraform-aks-pipeline"
}

variable "github_repo_id" {
  type    = string
  default = "1374105247"
}
