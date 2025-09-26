import { cleanupTempFolders, logger, removeFolder } from './src';

beforeAll(() => {
    removeFolder('./reports/allure-reports');
}, 180_000);

beforeEach(() => {
    logger.info(`Running test: ${expect.getState().currentTestName}`);
});

afterAll(() => {
    cleanupTempFolders();
}, 180_000);
