interface ServerNotify
  """
  Notifications about the creation and closing of `TCPConnection`s
  within HTTP servers.
  """
  fun ref listening(server: Server ref) =>
    """
    Called when we are listening.
    """
    None

  fun ref not_listening(server: Server ref) =>
    """
    Called when we fail to listen.
    """
    None

  fun ref closed(server: Server ref) =>
    """
    Called when we stop listening.
    """
    None
