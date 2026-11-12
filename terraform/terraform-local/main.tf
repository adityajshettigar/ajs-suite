terraform {
  required_version = ">= 1.5"
  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

provider "docker" {}

resource "docker_network" "ajs_demo" {
  name = "${var.project_name}-net"
}

resource "docker_volume" "sessions" {
  name = "${var.project_name}-sessions"
}

resource "docker_image" "nginx" {
  name         = "nginx:alpine"
  keep_locally = false
}

resource "docker_container" "demo" {
  name  = "${var.project_name}-web"
  image = docker_image.nginx.image_id

  ports {
    internal = 80
    external = var.host_port
  }

  networks_advanced {
    name = docker_network.ajs_demo.name
  }
}
