variable "project_name" {
  description = "Prefix for resource names."
  type        = string
  default     = "ajs-tf-demo"
}

variable "host_port" {
  description = "Host port to expose the demo container."
  type        = number
  default     = 8080
}
