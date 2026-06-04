//! SMS delivery for OTP codes. `console` prints to the log (dev); `sns` sends a
//! real message via Amazon SNS; `twilio` via the Twilio REST API.

use slide_core::error::{AppError, AppResult};

#[derive(Clone)]
pub enum SmsSender {
    Console,
    Sns {
        client: aws_sdk_sns::Client,
        sender_id: Option<String>,
    },
    Twilio {
        account_sid: String,
        auth_token: String,
        from: String,
        http: reqwest_like::Client,
    },
}

impl SmsSender {
    pub async fn from_config(cfg: &crate::config::Config) -> Self {
        match cfg.sms_provider.as_str() {
            "sns" => {
                let region = aws_config::Region::new(cfg.aws_region.clone());
                let shared = aws_config::defaults(aws_config::BehaviorVersion::latest())
                    .region(region)
                    .load()
                    .await;
                let sender_id = if cfg.sms_sender_id.is_empty() {
                    None
                } else {
                    Some(cfg.sms_sender_id.clone())
                };
                SmsSender::Sns {
                    client: aws_sdk_sns::Client::new(&shared),
                    sender_id,
                }
            }
            "twilio" => SmsSender::Twilio {
                account_sid: cfg.twilio_account_sid.clone(),
                auth_token: cfg.twilio_auth_token.clone(),
                from: cfg.twilio_from.clone(),
                http: reqwest_like::Client::new(),
            },
            _ => SmsSender::Console,
        }
    }

    pub async fn send_code(&self, phone: &str, code: &str) -> AppResult<()> {
        match self {
            SmsSender::Console => {
                tracing::info!(phone = %phone, code = %code, "📲 [dev] OTP code");
                Ok(())
            }
            SmsSender::Sns { client, sender_id } => {
                use aws_sdk_sns::types::MessageAttributeValue;
                let body = format!("Your Slide code is {code}");
                let mut req = client
                    .publish()
                    .phone_number(phone)
                    .message(body)
                    // Transactional = highest delivery priority for OTP codes.
                    .message_attributes(
                        "AWS.SNS.SMS.SMSType",
                        MessageAttributeValue::builder()
                            .data_type("String")
                            .string_value("Transactional")
                            .build()
                            .map_err(|e| AppError::unavailable(format!("sns attr: {e}")))?,
                    );
                if let Some(sid) = sender_id {
                    req = req.message_attributes(
                        "AWS.SNS.SMS.SenderID",
                        MessageAttributeValue::builder()
                            .data_type("String")
                            .string_value(sid)
                            .build()
                            .map_err(|e| AppError::unavailable(format!("sns attr: {e}")))?,
                    );
                }
                req.send()
                    .await
                    .map_err(|e| AppError::unavailable(format!("sns send failed: {e}")))?;
                tracing::info!(phone = %phone, "OTP sent via SNS");
                Ok(())
            }
            SmsSender::Twilio {
                account_sid,
                auth_token,
                from,
                http,
            } => {
                let url = format!(
                    "https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json"
                );
                let body = format!("Your Slide code is {code}");
                let params = [("To", phone), ("From", from.as_str()), ("Body", &body)];
                http.post_form(&url, account_sid, auth_token, &params)
                    .await
                    .map_err(|e| AppError::unavailable(format!("sms send failed: {e}")))?;
                Ok(())
            }
        }
    }
}

/// Minimal HTTP client wrapper over the `reqwest` crate kept behind a tiny
/// shim so the rest of the code doesn't depend on its surface directly.
pub mod reqwest_like {
    #[derive(Clone)]
    pub struct Client(reqwest::Client);

    impl Client {
        pub fn new() -> Self {
            Client(reqwest::Client::new())
        }

        pub async fn post_form(
            &self,
            url: &str,
            basic_user: &str,
            basic_pass: &str,
            params: &[(&str, &str)],
        ) -> Result<(), String> {
            let resp = self
                .0
                .post(url)
                .basic_auth(basic_user, Some(basic_pass))
                .form(params)
                .send()
                .await
                .map_err(|e| e.to_string())?;
            if resp.status().is_success() {
                Ok(())
            } else {
                Err(format!("status {}", resp.status()))
            }
        }
    }

    impl Default for Client {
        fn default() -> Self {
            Self::new()
        }
    }
}
