output "container_name" { value = docker_container.demo.name }
output "network_name"   { value = docker_network.ajs_demo.name }
output "url"            { value = "http://localhost:${var.host_port}" }
