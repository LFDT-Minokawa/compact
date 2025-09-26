const fs = require('fs');

function extractErrorMessages(filePath) {

    const fileContent = fs.readFileSync(filePath, 'utf8');
    const regex = /parse error:([^\n]+)/g;

    let errorMessages = new Set;
    let match;

    while ((match = regex.exec(fileContent)) !== null) {
        errorMessages.add(match[1].trim());
    }
    return errorMessages;
}

const filePath = 'build_parse.txt';
const errors = extractErrorMessages(filePath);

console.log(errors);

fs.writeFileSync('output.txt', Array.from(errors).join('\n'));
