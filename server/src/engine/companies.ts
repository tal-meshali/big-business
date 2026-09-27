/** Company identities for Big Business. Index is the CompanyId. */
export type CompanyId = 0 | 1 | 2 | 3 | 4 | 5;

export interface Company {
  id: CompanyId;
  key: string;
  name: string;
  shares: number;
  color: string;
}

export const COMPANIES: ReadonlyArray<Company> = [
  { id: 0, key: 'solar', name: 'Sunny Side Solar', shares: 5, color: '#F5C542' },
  { id: 1, key: 'foods', name: 'Pinecone Foods', shares: 6, color: '#4CAF6A' },
  { id: 2, key: 'freight', name: 'Tidewater Freight', shares: 7, color: '#3B82F6' },
  { id: 3, key: 'robotics', name: 'Cogwheel Robotics', shares: 8, color: '#F4813F' },
  { id: 4, key: 'air', name: 'Nimbus Air', shares: 9, color: '#8B5CF6' },
  { id: 5, key: 'motors', name: 'Redline Motors', shares: 10, color: '#E5484D' },
];

export const COMPANY_COUNT = 6;
export const TOTAL_SHARES = 45;
export const REMOVED_SHARES = 5;
export const HAND_SIZE = 3;
export const STARTING_COINS = 10;
export const MIN_SEATS = 3;
export const MAX_SEATS = 7;
export const GOLD_VALUE = 3;
