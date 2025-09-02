module ApplicationHelper
  def messages_once(**locals)
    return if @__messages_rendered
    @__messages_rendered = true
    render("shared/messages", **locals)
  end
end
