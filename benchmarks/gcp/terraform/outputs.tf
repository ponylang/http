output "server_ip" {
  value = google_compute_instance.bench_server.network_interface.0.access_config.0.nat_ip
}

output "client_ip" {
  value = google_compute_instance.bench_client.network_interface.0.access_config.0.nat_ip
}
