import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import ingestLocalFiles from '@salesforce/apex/CvUploadController.ingestLocalFiles';
import listRecentCandidates from '@salesforce/apex/CvUploadController.listRecentCandidates';
import getCandidateDetail from '@salesforce/apex/CvUploadController.getCandidateDetail';
import { extractPdfEmbeddedText } from './pdfTextExtractor';

export default class CvUploadWorkspace extends LightningElement {
    @track results = [];
    @track candidates = [];
    @track selected;
    @track error;
    @track selectedFileNames = [];
    @track statusMessage = '';
    @track uploading = false;
    pendingFiles = [];
    wiredCandidatesResult;

    acceptedFormats = '.pdf,.doc,.docx,.txt';

    @wire(listRecentCandidates)
    wiredCandidates(value) {
        this.wiredCandidatesResult = value;
        const { data, error } = value;
        if (data) {
            this.candidates = data;
            this.error = undefined;
        } else if (error) {
            this.error = this.reduceError(error);
        }
    }

    get hasResults() {
        return this.results && this.results.length > 0;
    }

    get hasSelection() {
        return !!this.selected;
    }

    get hasPendingFiles() {
        return this.pendingFiles && this.pendingFiles.length > 0;
    }

    get skillRows() {
        return this.selected?.Skills__r || [];
    }

    get experienceRows() {
        return this.selected?.Experiences__r || [];
    }

    get educationRows() {
        return this.selected?.Educations__r || [];
    }

    get issueRows() {
        return this.selected?.Data_Issues__r || [];
    }

    handleFilesChosen(event) {
        const list = event.target.files ? Array.from(event.target.files) : [];
        this.pendingFiles = list;
        this.selectedFileNames = list.map((f, idx) => ({ id: `${idx}-${f.name}`, name: f.name }));
        this.results = [];
        this.error = undefined;
        this.statusMessage = '';
        if (list.length) {
            this.toast('Files selected', `${list.length} file(s) ready. Click Process to continue.`, 'info');
        }
    }

    fileToBase64(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => {
                const result = reader.result || '';
                const comma = String(result).indexOf(',');
                resolve(comma >= 0 ? String(result).substring(comma + 1) : String(result));
            };
            reader.onerror = () => reject(reader.error || new Error('Failed to read file'));
            reader.readAsDataURL(file);
        });
    }

    async extractPdfText(file) {
        const buffer = await file.arrayBuffer();
        return extractPdfEmbeddedText(buffer);
    }

    async buildPayload(file) {
        const name = file.name || 'upload.bin';
        const lower = name.toLowerCase();
        let extractedText = '';

        if (lower.endsWith('.pdf')) {
            this.statusMessage = `Extracting text from ${name}…`;
            try {
                extractedText = await this.extractPdfText(file);
            } catch (e) {
                // Continue with empty text → Apex stub/uncertain path rather than hanging.
                this.toast('PDF extract limited', e.message || 'Could not read PDF text layer.', 'warning');
                extractedText = '';
            }
            if (!extractedText) {
                this.toast(
                    'No text found in PDF',
                    `${name} may be image-only or use an unsupported encoding. We’ll still create a card.`,
                    'warning'
                );
            } else {
                this.statusMessage = `Extracted ${extractedText.length} characters from ${name}`;
            }
        } else if (lower.endsWith('.txt') || lower.endsWith('.md')) {
            this.statusMessage = `Reading ${name}…`;
            extractedText = await file.text();
        }

        this.statusMessage = `Uploading ${name}…`;
        const base64Data = await this.fileToBase64(file);
        return { fileName: name, base64Data, extractedText };
    }

    async handleProcess() {
        if (!this.pendingFiles.length) {
            this.toast('Nothing to process', 'Choose one or more CV files first.', 'warning');
            return;
        }
        this.uploading = true;
        this.error = undefined;
        this.results = [];
        try {
            const allResults = [];
            for (let i = 0; i < this.pendingFiles.length; i++) {
                const file = this.pendingFiles[i];
                this.statusMessage = `Processing ${i + 1}/${this.pendingFiles.length}: ${file.name}`;
                const payload = await this.buildPayload(file);
                this.statusMessage = `Creating Candidate Card for ${file.name}…`;
                const batch = await ingestLocalFiles({ payloads: [payload] });
                allResults.push(...(batch || []));
            }
            this.results = allResults.map((r, idx) => ({
                ...r,
                rowKey: r.candidateId || `row-${idx}`
            }));
            this.pendingFiles = [];
            this.selectedFileNames = [];
            const input = this.template.querySelector('input.cv-file-input');
            if (input) {
                input.value = '';
            }
            await refreshApex(this.wiredCandidatesResult);
            this.statusMessage = '';
            this.toast('Done', `${this.results.length} candidate card(s) created.`, 'success');
        } catch (e) {
            this.error = this.reduceError(e);
            this.statusMessage = '';
            this.toast('Could not process CV', this.error, 'error');
        } finally {
            this.uploading = false;
        }
    }

    async handleSelect(event) {
        event.preventDefault();
        const candidateId = event.currentTarget.dataset.id;
        try {
            this.selected = await getCandidateDetail({ candidateId });
        } catch (e) {
            this.error = this.reduceError(e);
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    reduceError(error) {
        if (!error) return 'Unknown error';
        if (Array.isArray(error.body)) {
            return error.body.map((e) => e.message).join(', ');
        }
        if (error.body && typeof error.body.message === 'string') {
            return error.body.message;
        }
        return error.message || 'Unknown error';
    }
}
