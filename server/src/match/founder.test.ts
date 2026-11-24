import { describe, expect, it } from 'vitest';
import { clashWith, COLOR_SAME, companiesManifest, emptyRow, LOGO_SAME, NAME_SAME, nameProblem, normalizeCompaniesRow, setCompany, shortName, SHORT_SAME } from './founder';

describe('company names', () => {
  it('takes ordinary business names in several alphabets', () => {
    for (const n of ['Acme', 'Smith & Co.', "O'Neil Bakery", 'Up-Start 2000', 'Café Noir', 'שוקו בע"מ'.replace('"', ''), 'Ωmega Labs', 'Ab']) {
      expect(nameProblem(n), n).toBeNull();
    }
  });

  it('refuses bad shapes, lengths, characters and words', () => {
    expect(nameProblem('A')).toMatch('characters');
    expect(nameProblem('A very long company name here')).toMatch('characters');
    expect(nameProblem('Acme  Corp')).toMatch('Start with');
    expect(nameProblem('-Acme')).toMatch('Start with');
    expect(nameProblem('Acme-')).toMatch('Start with');
    expect(nameProblem('& Sons')).toMatch('Start with');
    expect(nameProblem('Co..')).toMatch('Start with');
    expect(nameProblem('Acme 🚀')).toMatch('letters, numbers');
    expect(nameProblem('Call 0501234567')).toMatch('numbers');
    expect(nameProblem('1234')).toMatch('numbers');
    expect(nameProblem('Sh1t Inc')).toBe('Pick a different name.');
    expect(nameProblem('Big Business')).toBe('Pick a different name.');
    expect(nameProblem('Ass Ltd')).toBe('Pick a different name.');
    // Blocked short words only count on their own.
    expect(nameProblem('Classic Glass')).toBeNull();
    expect(nameProblem('Peacock Air')).toBeNull();
  });

  it('reads through look-alikes and split words without refusing ordinary names', () => {
    for (const n of ['Fuсk Co', 'Phuck Inc', 'Fvck Inc', 'Fu Ck Corp', 'Cocks & Co', 'Nazis', 'Admins Ltd', 'Shitty Air', 'Fück Co', 'Fuuuck Co', 'Kunt Co', 'Nazism', 'Raped Inc']) {
      expect(nameProblem(n), n).toBe('Pick a different name.');
    }
    for (const n of ['Badminton Club', 'Scunthorpe United', 'Push It Co', 'Wash It Co', 'Cogs Hit', 'Shiitake Co', 'Bit Chain', 'Pass Hole', 'Snigger Co', 'Essex Foods', 'Title Deeds', 'Penistone Mills', 'Rapeseed Oil', 'Sexton Bakery', 'Glasses Co', 'Coffee Pool']) {
      expect(nameProblem(n), n).toBeNull();
    }
  });
});

describe('company set rules', () => {
  it('keeps the six companies apart in name, colour and logo', () => {
    const row = emptyRow();
    expect(clashWith(row, 2, { name: 'Rocket Mail', color: 'teal', logo: 'rocket', picture: null })).toBe('');
    expect(clashWith(row, 2, { name: 'nimbus air', color: 'teal', logo: 'rocket', picture: null })).toBe(NAME_SAME);
    expect(clashWith(row, 2, { name: 'Rocket Mail', color: 'red', logo: 'rocket', picture: null })).toBe(COLOR_SAME);
    expect(clashWith(row, 2, { name: 'Rocket Mail', color: 'teal', logo: 'sun', picture: null })).toBe(LOGO_SAME);
    // Too-alike colours and logos count as taken; so does the same band name.
    expect(clashWith(row, 2, { name: 'Rocket Mail', color: 'lime', logo: 'rocket', picture: null })).toBe(COLOR_SAME);
    expect(clashWith(row, 2, { name: 'Rocket Mail', color: 'teal', logo: 'mountain', picture: null })).toBe(LOGO_SAME);
    expect(clashWith(row, 2, { name: 'The Solar Shop Co', color: 'teal', logo: 'rocket', picture: null })).toBe(SHORT_SAME);
    expect(shortName('The Rocket Shop', 2)).toBe('Rocket');
    expect(shortName('Acme Co', 2)).toBe('Acme Co');
    expect(shortName('Sunny Side Solar', 0)).toBe('Solar');
    // A slot may reuse its own standard colour and logo.
    expect(clashWith(row, 2, { name: 'Rocket Mail', color: 'blue', logo: 'anchor', picture: null })).toBe('');
  });

  it('drops invalid stored entries and shows only approved pictures', () => {
    const row = normalizeCompaniesRow({ companies: [{ name: 'Acme', color: 'teal', logo: 'star', picture: 'a'.repeat(64) }, { name: 'x', color: 'teal', logo: 'star' }, 'junk'], active: true });
    expect(row.companies[0]).toEqual({ name: 'Acme', color: 'teal', logo: 'star', picture: 'a'.repeat(64) });
    expect(row.companies.slice(1)).toEqual([null, null, null, null, null]);
    expect(companiesManifest(row, () => false)![0]).toEqual({ name: 'Acme', color: 'teal', logo: 'star', picture: null });
    expect(companiesManifest(row, () => true)![0]!.picture).toBe('a'.repeat(64));
    expect(companiesManifest({ ...row, active: false }, () => true)).toBeNull();
    expect(companiesManifest(setCompany(row, 0, null), () => true)).toBeNull();
  });
});

