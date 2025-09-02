class ApplicationMailer < ActionMailer::Base
  default from: "Resumo Livre <noreply@resumolivre.com>",
          reply_to: "noreply@resumolivre.com"
  layout "mailer"
end
