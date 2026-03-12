# Support Page Content

Host this content on a website (GitHub Pages recommended) for your Support URL.

---

## Molten - Support

**Last Updated**: March 13, 2026

### Welcome to Molten Support

Molten is a privacy-first local AI chat application for macOS, iOS, and iPadOS. This page provides support resources and contact information.

---

## Quick Start

### Getting Started

1. **Install a model provider** (choose one):
   - [Ollama](https://ollama.ai) - Popular local LLM runtime
   - [Swama](https://github.com/Trans-N-ai/swama) - MLX-optimized for Apple Silicon
   - Apple Foundation Models - Built-in on macOS 26.0+

2. **Download a model**:
   ```bash
   ollama pull llama2
   # or
   ollama pull qwen2.5
   ```

3. **Open Molten** and select your model from the dropdown

4. **Start chatting!**

### Video Tutorials

- [Setting up Ollama](https://ollama.ai/download)
- [Molten Overview](LINK_TO_YOUR_VIDEO)

---

## Frequently Asked Questions

### General

**Q: Is Molten free?**  
A: Yes, Molten is completely free and open source.

**Q: Does Molten collect my data?**  
A: No. Molten collects zero data. All processing happens locally on your device.

**Q: Do I need internet to use Molten?**  
A: No. Once models are installed, everything works offline.

**Q: What models does Molten support?**  
A: Any model that runs on Ollama, Swama, or Apple Foundation Models. Popular choices: Llama 2, Llama 3, Qwen, Mistral.

---

### Troubleshooting

**Q: No models appear in the model selector**

**A:** Make sure a model provider is running:
1. Install Ollama from https://ollama.ai
2. Start Ollama: `ollama serve`
3. Pull a model: `ollama pull llama2`
4. Restart Molten

**Q: Responses are very slow**

**A:** Local models require significant resources:
- Ensure you're using Apple Silicon (M1/M2/M3)
- Try smaller models (7B or 8B parameters)
- Close other applications
- Check Activity Monitor for memory pressure

**Q: App crashes when streaming**

**A:** This is usually a memory issue:
- Use smaller models
- Reduce concurrent applications
- Restart your Mac
- Report the issue with crash logs

**Q: Stop button doesn't revert to send button**

**A:** This was fixed in v1.0.0. Update to the latest version.

---

### Technical

**Q: What are the system requirements?**

**A:**
- macOS 14.0+ (Sonoma or later)
- iOS 17.0+
- iPadOS 17.0+
- Apple Silicon Mac recommended (M1, M2, M3)

**Q: Can I use Molten on Intel Macs?**

**A:** Yes, but you'll need to run Ollama or Swama separately. Apple Foundation Models require Apple Silicon.

**Q: Where are conversations stored?**

**A:** Locally on your device using SwiftData. No cloud sync.

**Q: Can I export my conversations?**

**A:** Use the copy button (📋) to copy conversation as text or JSON.

---

### Privacy & Security

**Q: Is my data really private?**

**A:** Yes. Molten:
- Collects no data
- Makes no network calls except to localhost
- Has no analytics or tracking
- Is open source for audit

**Q: Is Molten open source?**

**A:** Yes! View the code at https://github.com/OnDemandWorld/molten

**Q: Can I audit the code myself?**

**A:** Absolutely! The entire codebase is open source under Apache License 2.0.

---

## Known Issues

### Current Limitations

- **iOS/iPadOS**: Requires separate model provider setup
- **Apple Foundation Models**: Only available on macOS 26.0+
- **Image Support**: Limited to specific models (LLaVA, etc.)

### Bug Reports

Found a bug? Report it on GitHub: https://github.com/OnDemandWorld/molten/issues

Include:
- macOS/iOS version
- Molten version
- Steps to reproduce
- Expected vs actual behavior
- Screenshots (if applicable)

---

## Feature Requests

Have an idea? Submit it on GitHub: https://github.com/OnDemandWorld/molten/discussions

### Planned Features
- [ ] Export/import conversations
- [ ] Custom themes
- [ ] More keyboard shortcuts
- [ ] Plugin system for providers
- [ ] Advanced conversation management

---

## Contact

### Support Channels

**GitHub Issues**: https://github.com/OnDemandWorld/molten/issues  
**GitHub Discussions**: https://github.com/OnDemandWorld/molten/discussions  
**Email**: [YOUR_EMAIL_HERE]

### Response Time

We aim to respond within 48 hours on weekdays.

---

## Additional Resources

### Documentation

- [README.md](https://github.com/OnDemandWorld/molten/blob/main/README.md) - User guide
- [ARCHITECTURE.md](https://github.com/OnDemandWorld/molten/blob/main/ARCHITECTURE.md) - Technical details
- [CONTRIBUTING.md](https://github.com/OnDemandWorld/molten/blob/main/CONTRIBUTING.md) - How to contribute

### Model Providers

- [Ollama Documentation](https://ollama.ai/help)
- [Swama Documentation](https://github.com/Trans-N-ai/swama)
- [Apple Foundation Models](https://developer.apple.com/documentation/foundationmodels)

### Community

- [LocalAI Community](https://discord.gg/localai)
- [Ollama Discord](https://discord.gg/ollama)
- [r/LocalLLaMA](https://reddit.com/r/LocalLLaMA)

---

## Update History

### Version 1.0.0 (March 2026)
- Initial release
- Multi-provider support (Ollama, Swama, Apple)
- Streaming responses with analytics
- Conversation history
- Voice input & text-to-speech
- Dark/Light mode

---

## Legal

**License**: Apache License 2.0  
**Privacy Policy**: https://github.com/OnDemandWorld/molten/blob/main/PRIVACY.md  
**Terms of Use**: Use at your own risk. No warranty provided.

**Acknowledgments**: Based on the Enchanted project by Augustinas Malinauskas.

---

**Molten** - Local AI. On Your Terms. 🍎
