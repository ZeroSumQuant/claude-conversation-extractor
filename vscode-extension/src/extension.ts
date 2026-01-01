import * as vscode from 'vscode';
import * as child_process from 'child_process';
import * as path from 'path';

export function activate(context: vscode.ExtensionContext) {
	console.log('Claude Conversation Extractor is now active!');

	let startDisposable = vscode.commands.registerCommand('claude-extractor.start', () => {
		const terminal = vscode.window.createTerminal('Claude Extractor');
		terminal.show();
		terminal.sendText('claude-start');
	});

	let extractRecentDisposable = vscode.commands.registerCommand('claude-extractor.extractRecent', () => {
        vscode.window.showInputBox({
            prompt: "How many recent conversations to extract?",
            value: "5"
        }).then(value => {
            if (value) {
                const terminal = vscode.window.createTerminal('Claude Extractor');
                terminal.show();
                terminal.sendText(`claude-extract --recent ${value}`);
            }
        });
	});

	context.subscriptions.push(startDisposable);
	context.subscriptions.push(extractRecentDisposable);
}

export function deactivate() {}
