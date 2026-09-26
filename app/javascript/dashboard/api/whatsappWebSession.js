/* global axios */
import ApiClient from './ApiClient';

// WaDesk: link, re-link and log out WhatsApp Web inboxes.
class WhatsappWebSessionAPI extends ApiClient {
  constructor() {
    super('inboxes', { accountScoped: true });
  }

  get(inboxId) {
    return axios.get(`${this.url}/${inboxId}/whatsapp_web_session`);
  }

  reconnect(inboxId, linkMethod) {
    return axios.post(`${this.url}/${inboxId}/whatsapp_web_session/reconnect`, {
      link_method: linkMethod,
    });
  }

  logout(inboxId) {
    return axios.delete(`${this.url}/${inboxId}/whatsapp_web_session`);
  }
}

export default new WhatsappWebSessionAPI();
