import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import ask from '@salesforce/apex/CvAgentChatController.ask';

export default class CvAgentChat extends LightningElement {
    @track messages = [];
    @track draft = '';
    @track busy = false;
    @track error;
    _msgSeq = 0;

    get sendDisabled() {
        return this.busy || !this.draft || !this.draft.trim();
    }

    connectedCallback() {
        this.pushAssistant('Ask a question about candidates when you are ready.');
    }

    renderedCallback() {
        this.scrollChatToBottom();
    }

    handleDraftChange(event) {
        this.draft = event.target.value;
    }

    handleReset() {
        this.messages = [];
        this.error = undefined;
        this.pushAssistant('Conversation cleared. Ask a new question about candidates.');
    }

    async handleSend() {
        const text = (this.draft || '').trim();
        if (!text || this.busy) {
            return;
        }
        this.error = undefined;
        this.pushUser(text);
        this.draft = '';
        this.busy = true;

        try {
            const reply = await ask({ utterance: text, preferredCandidateId: null });
            this.pushAssistant(reply.message || (reply.success ? 'Done.' : 'No grounded answer.'));
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Chat request failed.';
            this.pushAssistant(this.error);
            this.toast('Chat failed', this.error, 'error');
        } finally {
            this.busy = false;
        }
    }

    pushUser(text) {
        this.messages = [
            ...this.messages,
            {
                id: `m-${++this._msgSeq}`,
                roleLabel: 'You',
                text,
                cssClass: 'bubble bubble-user slds-m-bottom_small'
            }
        ];
    }

    pushAssistant(text) {
        this.messages = [
            ...this.messages,
            {
                id: `m-${++this._msgSeq}`,
                roleLabel: 'CV Review Agent',
                text,
                cssClass: 'bubble bubble-agent slds-m-bottom_small'
            }
        ];
    }

    scrollChatToBottom() {
        const log = this.template.querySelector('.chat-log');
        if (log) {
            log.scrollTop = log.scrollHeight;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
