interface ServerNotify
  """
  Notifications about the creation and closing of `TCPConnection`s
  within HTTP servers.
  """
  fun ref listening(server: HTTPServer ref) =>
    """
    Called when we are listening.
    """
    None

  fun ref not_listening(server: HTTPServer ref) =>
    """
    Called when we fail to listen.
    """
    None

  fun ref closed(server: HTTPServer ref) =>
    """
    Called when we stop listening.
    """
    None
